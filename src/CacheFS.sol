pragma ton-solidity >= 0.51.0;

import "ICache.sol";
import "SyncFS.sol";

/* Base contract for the file system importing devices */
abstract contract CacheFS is ICacheFS, SyncFS {

    /* Store the file system cache information provided by a host device */
    function update_fs_cache(SuperBlock sb, mapping (uint16 => ProcessInfo) processes, mapping (uint16 => UserInfo) users,
                            mapping (uint16 => GroupInfo) groups, mapping (uint16 => Inode) inodes) external override accept {
        for ((uint16 i, Inode inode): inodes)
            _inodes[i] = inode;

        _proc = processes;
        _users = users;
        _groups = groups;
        _sb = sb;
    }

    function _init() internal override accept {
        _sync_fs_cache();
    }

    /* Print an internal debugging information about the file system state */
    function dump_fs(uint8 level) external view returns (string) {
        return _dump_fs(level, _sb, _inodes);
    }

    function flush_fs_cache() external override accept {
        _sync_fs_cache();
    }

    function _sync_fs_cache() internal {
        delete _sb;
        delete _inodes;
        ISourceFS(_source).query_fs_cache();
    }

}


