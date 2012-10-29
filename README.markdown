**zipzap** is a zip file I/O library for Mac OS X and iOS.

The zip file is an ideal container for compound Objective-C documents. Zip files are widely used and well understood. You can randomly access their parts. The format compresses decently and has extensive operating system and tool support. So we want to make this format an even easier choice for you. Thus, the library features:

* **Easy-to-use interface**: The public API offers just three classes! Yet you can look through zip files using familiar *NSArray* collections and properties. And you can zip, unzip and rezip zip files through familiar *NSData*, *NSStream* and Image I/O classes.
* **Efficient implementation**: We've optimized zip file reading and writing to reduce virtual memory pressure and disk file thrashing. Depending on how your compound document is organized, updating a single entry can be faster than writing the same data to a separate file.
* **File format compatibility**: Since *zipzap* closely follows the [zip file format specification](http://www.pkware.com/documents/casestudies/APPNOTE.TXT), it is works with most Mac, Linux and Windows zip tools.

Install
-------

As an independent project:

* In the Terminal, run `git clone https://github.com/pixelglow/zipzap.git`.
* Within the *zipzap* directory, open the *zipzap.xcodeproj* Xcode project.
* In the Xcode project, select either the *zipzap (OS X)* or the *zipzap (iOS)* scheme from the drop down.
* You can now build, test (Mac OS X only) or analyze with the selected scheme.
* The built libraries and test cases are in a subdirectory of *~/Library/Developer/Xcode/DerivedData*.

As a project integrated with your own workspace:

* In the Terminal, run `cd workspace` then `git submodule add https://github.com/pixelglow/zipzap.git`.
* In your Xcode workspace, choose the *File | Add Files to "workspace"* menu item, then within the *zipzap* directory pick the *zipzap.xcodeproj* Xcode project.
* In any target that uses *zipzap*, under *Build Phases*:
  * add *zipzap (OS X)* or *zipzap (iOS)* as a *Target Dependencies* item
  * add the corresponding *libzipzap.a* and any other library listed in the Require Link section below as *Link Binary with Libraries* items.
* You can now build, test or analyze those targets.

Use
---

Reading an existing zip file:

	ZZArchive* oldArchive = [ZZArchive archiveWithContentsOfURL:[NSURL fileURLWithPath:@"/tmp/old.zip"]];
	ZZArchiveEntry* firstArchiveEntry = oldArchive.entries[0];
	NSLog(@"The first entry's uncompressed size is %lu bytes.", firstArchiveEntry.uncompressedSize);
	NSLog(@"The first entry's data is: %@.", firstArchiveEntry.data);
	
Writing a new zip file:

	ZZMutableArchive* newArchive = [ZZArchive archiveWithContentsOfURL:[NSURL fileURLWithPath:@"/tmp/new.zip"]];
	newArchive.entries =
	@[
		[ZZArchiveEntry archiveEntryWithFileName:@"first.text"
										compress:YES
									   dataBlock:^{ return [@"hello, world" dataUsingEncoding:NSUTF8StringEncoding]; }]
	];
	
Updating an existing zip file:

	ZZMutableArchive* oldArchive = [ZZArchive archiveWithContentsOfURL:[NSURL fileURLWithPath:@"/tmp/old.zip"]];
	oldArchive.entries = [oldArchive.entries arrayByAddingObject:
		[ZZArchiveEntry archiveEntryWithFileName:@"second.text"
										compress:YES
									   dataBlock:^{ return [@"bye, world" dataUsingEncoding:NSUTF8StringEncoding]; }]
	];

Require
-------

* **Build**: Xcode 4.4 and later.
* **Link**: Only system libraries; no third-party libraries needed.
  * *ApplicationServices.framework* (Mac OS X) or *ImageIO.framework* (iOS)
  * *Foundation.framework*
  * *libz.dylib*
* **Run**: Mac OS X 10.7 (Lion) or iOS 4.0 and later.

Support
-------

* Follow us on Twitter: [@pixelglow](http://twitter.com/pixelglow).
* Raise an issue on [zipzap issues](https://github.com/pixelglow/zipzap/issues).

License
-------

*zipzap* is licensed with the BSD license.