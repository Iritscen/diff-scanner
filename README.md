# DiffScanner
I wrote this script to manage multiple copies of the same codebase that were residing on my hard drive. It's an interactive assistant that will ask you what to do about every file that differs between two folders: replace one copy with the other? View the differences between them (uses FileMerge, which comes with the Developer Tools in macOS)? Ignore this specific differing file?

Files only occurring on one side can be copied to the other side. As a safeguard, replaced files are moved to the Trash so you can review your changes before deleting the files.

DiffScanner will work fine for folders containing other types of files besides source code, though you won't be able to meaningfully view differences between files unless they are in a textual format that FileMerge understands. I only built this script to meet my own needs, but I would like it to be useful to others, so I'll consider feature requests, and please let me know if you encounter any bugs.

![Preview](https://github.com/Iritscen/diff-scanner/blob/master/preview.png)