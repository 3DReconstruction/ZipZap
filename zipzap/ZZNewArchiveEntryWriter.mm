//
//  ZZNewArchiveEntryWriter.m
//  zipzap
//
//  Created by Glen Low on 9/10/12.
//  Copyright (c) 2012, Pixelglow Software. All rights reserved.
//

#include <zlib.h>

#import "ZZDeflateOutputStream.h"
#import "ZZNewArchiveEntryWriter.h"
#import "ZZStoreOutputStream.h"
#import "ZZHeaders.h"

namespace ZZDataConsumer
{
	static size_t putBytes (void* info, const void* buffer, size_t count)
	{
		return [(__bridge ZZDeflateOutputStream*)info write:(const uint8_t*)buffer maxLength:count];
	}

	static CGDataConsumerCallbacks callbacks =
	{
		&putBytes,
		NULL
	};
}

@interface ZZNewArchiveEntryWriter ()

- (ZZCentralFileHeader*)centralFileHeader;
- (ZZLocalFileHeader*)localFileHeader;

@end

@implementation ZZNewArchiveEntryWriter
{
	NSMutableData* _centralFileHeader;
	NSMutableData* _localFileHeader;
	NSInteger _compressionLevel;
	NSData* (^_dataBlock)();
	void (^_streamBlock)(NSOutputStream* stream);
	void (^_dataConsumerBlock)(CGDataConsumerRef dataConsumer);
}

- (id)initWithFileName:(NSString*)fileName
			  fileMode:(mode_t)fileMode
		  lastModified:(NSDate*)lastModified
	  compressionLevel:(NSInteger)compressionLevel
			 dataBlock:(NSData*(^)())dataBlock
		   streamBlock:(void(^)(NSOutputStream* stream))streamBlock
	 dataConsumerBlock:(void(^)(CGDataConsumerRef dataConsumer))dataConsumerBlock;
{
	if ((self = [super init]))
	{
		// allocate central, local file headers with enough space for file name
		NSRange fileNameRange = NSMakeRange(0, fileName.length);
		_centralFileHeader = [NSMutableData dataWithLength:sizeof(ZZCentralFileHeader) + fileNameRange.length];
		_localFileHeader = [NSMutableData dataWithLength:sizeof(ZZLocalFileHeader) + fileNameRange.length];
		
		ZZCentralFileHeader* centralFileHeader = [self centralFileHeader];
		centralFileHeader->signature = ZZCentralFileHeader::sign;

		ZZLocalFileHeader* localFileHeader = [self localFileHeader];
		localFileHeader->signature = ZZLocalFileHeader::sign;

		// made by = 3.0, needed to extract = 1.0
		centralFileHeader->versionMadeBy = 0x1e;
		centralFileHeader->fileAttributeCompatibility = ZZFileAttributeCompatibility::unix;
		centralFileHeader->versionNeededToExtract = localFileHeader->versionNeededToExtract = 0x000a;
		
		// general purpose flag = approximate compression level + use of data descriptor (0x8)
		uint32_t compressionFlag;
		switch (compressionLevel)
		{
			case -1:
			default:
				compressionFlag = 0x0;
				break;
			case 1:
			case 2:
				// super fast (-es)
				compressionFlag = 0x3;
				break;
			case 3:
			case 4:
				// fast (-ef)
				compressionFlag = 0x2;
				break;
			case 5:
			case 6:
			case 7:
				compressionFlag = 0x0;
				break;
			case 8:
			case 9:
				compressionFlag = 0x1;
				break;
		}
		centralFileHeader->generalPurposeBitFlag = localFileHeader->generalPurposeBitFlag = compressionFlag | 0x8;

		centralFileHeader->compressionMethod = localFileHeader->compressionMethod = compressionLevel ? ZZCompressionMethod::deflated : ZZCompressionMethod::stored;
		
		// convert last modified Foundation date into MS-DOS time + date
		NSCalendar* gregorianCalendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar];
		NSDateComponents* lastModifiedComponents = [gregorianCalendar components:NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit
													| NSHourCalendarUnit | NSMinuteCalendarUnit | NSSecondCalendarUnit
																		fromDate:lastModified];
		centralFileHeader->lastModFileTime = localFileHeader->lastModFileTime = lastModifiedComponents.second >> 1 | lastModifiedComponents.minute << 5 | lastModifiedComponents.hour << 11;
		centralFileHeader->lastModFileDate = localFileHeader->lastModFileDate = lastModifiedComponents.day | lastModifiedComponents.month << 5 | (lastModifiedComponents.year - 1980) << 9;
		
		// crc32, compressed size and uncompressed size are zero; real values will be computed and written in data descriptor
		centralFileHeader->crc32 = localFileHeader->crc32 = 0;
		centralFileHeader->compressedSize = localFileHeader->compressedSize = 0;
		centralFileHeader->uncompressedSize = localFileHeader->uncompressedSize = 0;
		
		centralFileHeader->fileNameLength = localFileHeader->fileNameLength = fileName.length;
		centralFileHeader->extraFieldLength = localFileHeader->extraFieldLength = 0;
		centralFileHeader->fileCommentLength = 0;
		
		centralFileHeader->diskNumberStart = 0;
		
		// external file attributes are UNIX file attributes
		centralFileHeader->internalFileAttributes = 0;
		centralFileHeader->externalFileAttributes = fileMode << 16;
		
		// relative offset is zero but will be updated when local file is written
		centralFileHeader->relativeOffsetOfLocalHeader = 0;
		
		// filename is at end of central header, local header
		[fileName getBytes:centralFileHeader->fileName()
				 maxLength:fileNameRange.length
				usedLength:NULL
				  encoding:NSASCIIStringEncoding
				   options:0
					 range:fileNameRange
			remainingRange:NULL];
		[fileName getBytes:localFileHeader->fileName()
				 maxLength:fileNameRange.length
				usedLength:NULL
				  encoding:NSASCIIStringEncoding
				   options:0
					 range:fileNameRange
			remainingRange:NULL];
		
		_compressionLevel = compressionLevel;
		_dataBlock = dataBlock;
		_streamBlock = streamBlock;
		_dataConsumerBlock = dataConsumerBlock;
		
	}
	return self;
}

- (ZZCentralFileHeader*)centralFileHeader
{
	return (ZZCentralFileHeader*)_centralFileHeader.mutableBytes;
}

- (ZZLocalFileHeader*)localFileHeader
{
	return (ZZLocalFileHeader*)_localFileHeader.mutableBytes;
}

- (void)writeLocalFileToFileHandle:(NSFileHandle*)fileHandle
{
	// free any temp objects created while writing, especially via the callbacks which we don't control
	@autoreleasepool
	{
		ZZCentralFileHeader* centralFileHeader = [self centralFileHeader];
		
		// save current offset, then write out all of local file to the file handle
		centralFileHeader->relativeOffsetOfLocalHeader = (uint32_t)[fileHandle offsetInFile];
		[fileHandle writeData:_localFileHeader];
		
		ZZDataDescriptor dataDescriptor;
		dataDescriptor.signature = ZZDataDescriptor::sign;
		
		if (_compressionLevel)
		{
			// use of one the blocks to write to a stream that deflates directly to the output file handle
			ZZDeflateOutputStream* outputStream = [[ZZDeflateOutputStream alloc] initWithFileHandle:fileHandle
																				   compressionLevel:_compressionLevel];
			[outputStream open];
			if (_dataBlock)
			{
				NSData* data = _dataBlock();
				
				const uint8_t* bytes;
				NSUInteger bytesToWrite;
				NSUInteger bytesWritten;
				for (bytes = (const uint8_t*)data.bytes, bytesToWrite = data.length;
					 bytesToWrite > 0;
					 bytes += bytesWritten, bytesToWrite -= bytesWritten)
					bytesWritten = [outputStream write:bytes maxLength:bytesToWrite];
			}
			else if (_streamBlock)
				_streamBlock(outputStream);
			else if (_dataConsumerBlock)
			{
				CGDataConsumerRef dataConsumer = CGDataConsumerCreate((__bridge void*)outputStream, &ZZDataConsumer::callbacks);
				_dataConsumerBlock(dataConsumer);
				CGDataConsumerRelease(dataConsumer);
			}
			
			[outputStream close];
			
			dataDescriptor.crc32 = outputStream.crc32;
			dataDescriptor.compressedSize = outputStream.compressedSize;
			dataDescriptor.uncompressedSize = outputStream.uncompressedSize;
		}
		else
		{
			// use of one the blocks to write to a stream that just outputs to the output file handle
			if (_dataBlock)
			{
				NSData* data = _dataBlock();
				
				[fileHandle writeData:data];
				
				dataDescriptor.compressedSize = dataDescriptor.uncompressedSize = (uint32_t)data.length;
				dataDescriptor.crc32 = (uint32_t)crc32(0, (const Bytef*)data.bytes, dataDescriptor.uncompressedSize);
			}
			else
			{
				ZZStoreOutputStream* outputStream = [[ZZStoreOutputStream alloc] initWithFileHandle:fileHandle];
				[outputStream open];
				
				if (_streamBlock)
					_streamBlock(outputStream);
				else if (_dataConsumerBlock)
				{
					CGDataConsumerRef dataConsumer = CGDataConsumerCreate((__bridge void*)outputStream, &ZZDataConsumer::callbacks);
					_dataConsumerBlock(dataConsumer);
					CGDataConsumerRelease(dataConsumer);
				}
				
				[outputStream close];
				
				dataDescriptor.crc32 = outputStream.crc32;
				dataDescriptor.compressedSize = dataDescriptor.uncompressedSize = outputStream.size;
			}
		}
		
		// save the crc32, compressedSize, uncompressedSize, then write out the data descriptor
		centralFileHeader->crc32 = dataDescriptor.crc32;
		centralFileHeader->compressedSize = dataDescriptor.compressedSize;
		centralFileHeader->uncompressedSize = dataDescriptor.uncompressedSize;
		[fileHandle writeData:[NSData dataWithBytesNoCopy:&dataDescriptor
												   length:sizeof(dataDescriptor)
											 freeWhenDone:NO]];
	}
}

- (void)writeCentralFileHeaderToFileHandle:(NSFileHandle*)fileHandle
{
	[fileHandle writeData:_centralFileHeader];
}

@end
