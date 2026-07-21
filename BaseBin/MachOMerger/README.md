# MachOMerger

Merge two MachO binaries into one. The only supported use case at this moment is merging a dylib into dyld.

# Requirements
- The dylib to be injected *must* be compiled with `-Xlinker -add_split_seg_info -Xlinker -no_auth_data`
