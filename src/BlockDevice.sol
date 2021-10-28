pragma ton-solidity >= 0.51.0;

import "CacheFS.sol";
import "ICache.sol";

/* Generic block device hosting a generic file system */
contract BlockDevice is SyncFS, ISourceFS {

    uint16 constant STG_NONE    = 0;
    uint16 constant STG_PRIMARY = 1;
    uint16 constant STG_INODE   = 2;
    uint16 constant STG_ALT     = 4;
    uint16 constant STG_LOCAL   = 8;
    uint16 constant STG_SYNC    = 16;
    uint16 constant STG_TMP     = 32;
    uint16 constant STG_RO      = 64;

    address[] _readers;

    mapping (uint16 => FileMapS) public _file_table;
    string[] public _blocks;
    mapping (uint16 => FileS) public _fd_table;
    uint16 _fdc;

    constructor(DeviceInfo dev, address source) Internal (dev, source) public {
        _dev = dev;
        _source = source;
    }

    /* Mount a set of index nodes to the specified mount point of the primary file system */
    function mount_dir(uint16 mount_point_index, SuperBlock /*sb*/, mapping (uint16 => Inode) inodes) external override accept {
        uint n_files;
        uint16[] indices;
        uint counter = _sb.inode_count;
        Inode mount_point = _inodes[mount_point_index];

        for ((, Inode inode): inodes) {
            if (inode.mode != FT_DIR) {
                uint16 index = uint16(counter + n_files++);
                _inodes[index] = inode;
                mount_point = _add_dir_entry(mount_point, index, inode.file_name, _mode_to_file_type(inode.mode));
            }
        }
        _inodes[mount_point_index] = mount_point;
        _claim_inodes(n_files, n_files);

        indices.push(mount_point_index);
        for (uint i = counter; i < counter + n_files; i++)
            indices.push(uint16(i));
        _update_inodes_set(indices);
    }

    function request_mount(address source, uint16 mount_point, uint16 options) external view override accept {
        if ((options & MOUNT_DIR) > 0)
            IExportFS(source).rpc_mountd{value: 0.1 ton}(ROOT_DIR + mount_point);
    }

    /* Common file system update routine */
    function update_nodes(Session session, IOEvent[] ios) external override accept {
        for (IOEvent e: ios) {
            uint8 et = e.iotype;
            if (_is_add(et))
                _add_files(session, e.parent, et, e.args);
            if (_is_update(et))
                _change_attributes(session, e.parent, et, e.args);
        }
    }

    function update_user_info(Session session, UserEvent[] ues) external override accept {
        uint16 reg_u;
        uint16 sys_u;
        uint16 reg_g;
        uint16 sys_g;

        for (UserEvent e: ues) {
            (uint8 et, uint16 user_id, uint16 group_id, uint16 options, string user_name, string group_name, ) = e.unpack();

            bool is_system_account = (options & UAO_SYSTEM) > 0;
            bool create_home_dir = (options & UAO_CREATE_HOME_DIR) > 0;
            bool create_user_group = (options & UAO_CREATE_USER_GROUP) > 0;

            if (et == UA_ADD_USER) {
                if (create_user_group) {
                    _groups[group_id] = GroupInfo(group_name, is_system_account);
                    if (is_system_account)
                        sys_g++;
                    else
                        reg_g++;
                    _change_attributes(session, ROOT_DIR + 3, IO_UPDATE_TEXT_DATA, [Arg(format("{}\t{}", group_name, group_id), FT_REG_FILE, 30, ROOT_DIR + 3, 0)]);
                }
                if (create_home_dir)
                    _add_files(session, ROOT_DIR + 4, IO_MKDIR, [Arg("/home/" + user_name, FT_DIR, ENOENT, ROOT_DIR + 4, 0)]);
                _users[user_id] = UserInfo(group_id, user_name, group_name);
                if (is_system_account)
                    sys_u++;
                else
                    reg_u++;
                _change_attributes(session, ROOT_DIR + 4, IO_UPDATE_TEXT_DATA, [Arg(format("{}\t{}\t{}\t{}\t{}", user_name, user_id, group_id, group_name, "/home/" + user_name), FT_REG_FILE, 36, ROOT_DIR + 3, 0)]);
            } else if (et == UA_ADD_GROUP) {
                _groups[group_id] = GroupInfo(group_name, is_system_account);
                if (is_system_account)
                    sys_g++;
                else
                    reg_g++;
                _change_attributes(session, ROOT_DIR + 3, IO_UPDATE_TEXT_DATA, [Arg(format("{}\t{}", group_name, group_id), FT_REG_FILE, 30, ROOT_DIR + 3, 0)]);
            } else if (et == UA_DELETE_USER) {
                delete _users[user_id];
            } else if (et == UA_DELETE_GROUP) {
                delete _groups[group_id];
            } else if (et == UA_UPDATE_USER) {
                _users[user_id] = UserInfo(group_id, user_name, group_name);
            } else if (et == UA_UPDATE_GROUP) {
                _groups[group_id].group_name = group_name;
            } else if (et == UA_RENAME_GROUP) {
                _groups[group_id].group_name = group_name;
            } else if (et == UA_CHANGE_GROUP_ID) {
                _groups[group_id] = _groups[user_id];
                delete _groups[user_id];
            }
        }
        IUserTables(msg.sender).update_tables{value: 0.1 ton, flag: 1}(_users, _groups, reg_u, sys_u, reg_g, sys_g);
    }

    /* Write the text to a file at path */
    function write_to_file(Session session, string path, string text) external accept {
        (uint16 uid, uint16 gid, uint16 wd) = (session.uid, session.gid, session.wd);
        uint32 size = text.byteLength();
        uint16 n_blocks = uint16(size / _dev.blk_size) + 1;
        uint16 storage_type = STG_NONE;

        if (n_blocks > _sb.free_blocks)
            return;

        storage_type |= STG_PRIMARY;
        (uint16 b_start, uint16 b_count) = _write_text(text);

        string[] text_data;

        if (n_blocks == 1) {
            storage_type |= STG_INODE;
            text_data = [text];
        }

        uint16 counter = _sb.inode_count;
        Inode inode = _get_any_node(FT_REG_FILE, uid, gid, path, text_data);
        inode.file_size = size;
        _inodes[counter] = inode;
        _append_dir_entry(wd, counter, path, FT_REG_FILE);

        _file_table[counter] = FileMapS(storage_type, b_start, b_count);
        _claim_inodes(1, b_count);
        _update_inodes_set([wd, counter]);
    }

    function append_to_file(Session session, string path, string text) external accept {
        (uint16 uid, , ) = (session.uid, session.gid, session.wd);
        uint32 size = text.byteLength();
        uint16 n_blocks = uint16(size / _dev.blk_size) + 1;
        if (n_blocks > _sb.free_blocks)
            return;
        optional (uint16, Inode) p = _inodes.max();
        while (p.hasValue()) {
            (uint16 idx, Inode inode) = p.get();
            if (inode.file_name == path) {
                if (inode.owner_id != uid)
                    continue;
                (, uint16 b_count) = _write_text(text);
                inode.file_size += size;
                inode.last_modified = now;
                _inodes[idx] = inode;
                _file_table[idx].count += b_count;
                _update_inodes_set([idx]);
            }
            p = _inodes.prev(idx);
        }
    }

    /* Write blocks of textual data to a file identified by descriptor */
    function write_fd(uint16 pid, uint16 fd, uint16 start, string[] blocks) external accept {
        FileS f = _proc[pid].fd_table[fd];
        uint16 inode = f.inode;
        FileMapS fm = _file_table[inode];
        uint16 len = uint16(blocks.length);

        for (uint16 i = 0; i < len; i++)
            _blocks[fm.start + start + i] = blocks[i];
        f.bc += len;

        if (f.bc >= f.n_blk) {
            _inodes[inode].file_size = uint32(f.n_blk) * _sb.block_size + blocks[len - 1].byteLength();
            delete _proc[pid].fd_table[fd];
            _update_inodes_set([inode]);
        } else
            _proc[pid].fd_table[fd] = f;
    }

    /* Read blocks of textual data fron the files specified by index */
    function read_indices(Arg[] args) external view returns (string[][] texts) {
        return _read_indices(args);
    }

    /* next expected write for a file opened by the process */
    function next_write(uint16 pid, uint16 fdi) external view returns (uint16 start, uint16 count) {
        FileS f = _proc[pid].fd_table[fdi];
        start = f.bc;
        count = f.n_blk - f.bc;
        if (count > f.state)
            count = f.state;
    }

    /* Remove an expired index node */
    function remove_node(uint16 parent, uint16 victim) external accept {
        delete _inodes[victim];

        if (_inodes[parent].n_links < 2)
            delete _inodes[parent];
        _update_inodes_set([parent, victim]);
    }

    /* Print an internal debugging information about the file system state */
    function dump_fs(uint8 level) external view returns (string) {
        return _dump_fs(level, _sb, _inodes);
    }

    function _create_subdirs(Session session, uint16 pino, string[] files) internal {
        Arg[] args_create;
        for (string s: files)
            args_create.push(Arg(s, FT_DIR, 0, pino, 0));
        _add_files(session, pino, IO_MKDIR, args_create);
    }

    /* Directory entry helpers */
    function _append_dir_entry(uint16 dir_idx, uint16 ino, string file_name, uint8 file_type) internal {
        _inodes[dir_idx] = _add_dir_entry(_inodes[dir_idx], ino, file_name, file_type);
    }

    function _read_indices(Arg[] args) internal view returns (string[][] texts) {
        for (Arg arg: args) {
            uint16 idx = arg.idx;
            (uint16 storage_type, uint16 start, uint16 count) = _file_table[idx].unpack();
            if ((storage_type & STG_PRIMARY) > 0) {
                string text;
                uint cap = math.min(start + count, _blocks.length);
                for (uint i = start; i < cap; i++)
                    text.append(_blocks[i]);
                texts.push([text]);
            } else
                texts.push(_inodes[idx].text_data);
        }
    }

    function _change_attributes(Session session, uint16 pino, uint8 et, Arg[] args) internal {
        (, uint16 uid, uint16 gid, ) = session.unpack();
        uint16[] indices;
        uint len = args.length;
        Inode parent_inode = _inodes[pino];
        for (uint i = 0; i < len; i++) {
            (string path, , uint16 idx, uint16 parent, uint16 dir_idx) = args[i].unpack();
            if (et == IO_CHATTR) {
                Inode inode = _inodes[idx];
                if (inode.owner_id == uid || inode.group_id == gid) {
                    _inodes[idx].owner_id = parent_inode.owner_id;
                    _inodes[idx].group_id = parent_inode.group_id;
                    indices.push(idx);
                }
            }
            if (et == IO_PERMISSION) {
                _inodes[idx].mode = parent_inode.mode;
                indices.push(idx);
            }
            if (et == IO_UPDATE_TIME) {
                _inodes[idx].modified_at = parent_inode.modified_at;
                _inodes[idx].last_modified = parent_inode.last_modified;
                indices.push(idx);
            }
            if (et == IO_UNLINK) {
                _inodes[idx].n_links--;
                _inodes[parent].n_links--;
                if (_inodes[idx].n_links == 0) {
                    delete _inodes[idx];
                    string[] text = _inodes[parent].text_data;
                    for (uint16 j = dir_idx - 1; j < text.length - 1; j++)
                        text[j] = text[j + 1];
                    _inodes[parent].text_data = text;
                }
                indices.push(parent);
            }
            if (et == IO_HARDLINK) {
                _inodes[pino].n_links++;
                _append_dir_entry(pino, idx, path, FT_REG_FILE);
            }
            if (et == IO_UPDATE_TEXT_DATA) {
                Inode inode = _inodes[idx];
                inode.text_data.push(path);
                inode.file_size += uint32(path.byteLength());
                inode.modified_at = now;
                _inodes[idx] = inode;
                indices.push(idx);
            }
        }
        indices.push(pino);
        _sb.last_write_time = now;
        _update_inodes_set(indices);
    }

    function _add_files(Session session, uint16 pino, uint8 et, Arg[] args) internal {
        (uint16 pid, uint16 uid, uint16 gid, ) = session.unpack();
        uint n_files = args.length;
        uint16 counter = _sb.inode_count;
        uint total_blocks;
        bool copy_contents = et == IO_WR_COPY;
        bool allocate = et == IO_ALLOCATE;

        uint16[] inodes;
        uint16 symlink_target_idx;

        for (uint i = 0; i < n_files; i++) {
            (string s, , uint16 idx, uint16 parent, uint16 dir_idx) = args[i].unpack();
            uint16 ino = uint16(counter + i);
            if (et == IO_MKDIR) {
                _inodes[ino] = _get_dir_node(ino, parent, uid, gid, s);
                _append_dir_entry(parent, ino, s, FT_DIR);
                inodes.push(idx);
            } else if (et == IO_MKFILE) {
                string[] empty;
                _inodes[ino] = _get_any_node(FT_REG_FILE, uid, gid, s, empty);
                _append_dir_entry(parent, ino, s, FT_REG_FILE);
                inodes.push(parent);
            } else if (et == IO_SYMLINK) {
                if (i == 0) {
                    symlink_target_idx = parent;
                    counter--;
                } else {
                    _inodes[ino] = _get_symlink_node(uid, gid, s, _inodes[parent].text_data[dir_idx - 1]);
                    _append_dir_entry(symlink_target_idx, ino, s, FT_SYMLINK);
                    inodes.push(ino);
                    inodes.push(symlink_target_idx);
                }
            } else if (et == IO_WR_COPY) {
                uint16 target_storage_type = STG_NONE;
                uint b_start;
                uint b_count;
                uint b_batch_size;
                string[] contents;

                if (idx > 0)
                    contents = _inodes[idx].text_data;

                if (allocate) {
                    (b_start, b_count, b_batch_size) = _allocate_blocks(idx);
                    _proc[pid].fd_table[_fdc++] = FileS(0, ino, uint16(b_batch_size), 0, uint16(b_count), 0, uint16(b_count) * idx, s);
                }
                if (copy_contents) {
                    FileMapS source = _file_table[idx];
                    if ((source.storage_type & STG_PRIMARY) > 0)
                        (b_start, b_count) = _copy_blocks(source.start, source.count);
                    else if (!contents.empty())
                        (b_start, b_count) = _update_blocks(ino, _merge(contents));
                }
                if (b_start > 0 && b_count > 0)
                    target_storage_type |= STG_PRIMARY;
                _inodes[ino] = _get_any_node(FT_REG_FILE, uid, gid, s, contents);
                _append_dir_entry(parent, ino, s, FT_REG_FILE);
                _file_table[ino] = FileMapS(target_storage_type, uint16(b_start), uint16(b_count));
                total_blocks += b_count;
            }
        }

        _claim_inodes(n_files, math.max(total_blocks, n_files));
        inodes.push(pino);
        for (uint16 i = counter; i < counter + n_files; i++)
            inodes.push(i);
        _update_inodes_set(inodes);
    }

    /* Index node operations helpers */
    function _is_add(uint8 t) internal pure returns (bool) {
        return t == IO_WR_COPY || t == IO_MKFILE || t == IO_ALLOCATE || t == IO_MKDIR || t == IO_SYMLINK;
    }

    function _is_update(uint8 t) internal pure returns (bool) {
        return t == IO_CHATTR || t == IO_ACCESS || t == IO_PERMISSION || t == IO_UPDATE_TIME || t == IO_UNLINK || t == IO_HARDLINK || t == IO_TRUNCATE || t == IO_UPDATE_TEXT_DATA;
    }

    /* Block operations helpers */
    function _copy_blocks(uint s_start, uint s_count) internal returns (uint start, uint count) {
        SuperBlock sb = _sb;
        if (sb.file_system_state && sb.free_blocks > 0) {
            start = _blocks.length;
            count = math.min(sb.free_blocks, s_count);
            for (uint i = 0; i < count; i++)
                _blocks.push(_blocks[i + s_start]);
        }
    }

    function _allocate_blocks(uint kbytes) internal returns (uint start, uint count, uint batch_size) {
        SuperBlock sb = _sb;
        uint blk_size = _dev.blk_size;
        count = kbytes * 1024 / blk_size;
        batch_size = 16000 / blk_size;

        if (sb.file_system_state && sb.free_blocks > count)
            start = _blocks.length;
        string empty;
        for (uint i = 0; i < count; i++)
            _blocks.push(empty);
    }

    function _write_text(string text) internal returns (uint16, uint16) {
        uint blk_size = _dev.blk_size;
        uint len = text.byteLength();
        uint n_blocks = len / blk_size;
        uint start = _blocks.length;
        for (uint i = 0; i < n_blocks; i++)
            _blocks.push(text.substr(i * blk_size, blk_size));
        _blocks.push(text.substr(n_blocks * blk_size, len - n_blocks * blk_size));
        return (uint16(start), uint16(n_blocks + 1));
    }

    function _update_blocks(uint16 index, string text) internal returns (uint16 b_start, uint16 b_count) {
        uint16 storage_type;

        uint blk_size = _dev.blk_size;
        uint len = text.byteLength();
        uint n_blocks = len / blk_size + 1;
        uint16 blocks_len = uint16(_blocks.length);

        if (_file_table.exists(index)) {
            FileMapS fm = _file_table[index];
            (storage_type, b_start, b_count) = fm.unpack();
        } else
            b_start = blocks_len;

        if (b_count == 0)
            b_count = uint16(n_blocks);
        else
            if (n_blocks > b_count) {
                b_start = blocks_len;
                b_count = uint16(n_blocks);
            }

        for (uint i = 0; i < n_blocks; i++) {
            uint idx = b_start + i;
            string text_chunk = text.substr(i * blk_size, i + 1 < n_blocks ? blk_size : len - i * blk_size);
            if (idx < blocks_len)
                _blocks[idx] = text_chunk;
            else
                _blocks.push(text_chunk);
        }
    }

    function init_fs(SuperBlock sb, mapping (uint16 => Inode) inodes) external accept {
        _sb = sb;
        _inodes = inodes;
    }

    function _write_sb() internal view returns (string) {
        (bool file_system_state, bool errors_behavior, string file_system_OS_type, uint16 inode_count, uint16 block_count, uint16 free_inodes,
            uint16 free_blocks, uint16 block_size, uint32 created_at, uint32 last_mount_time, uint32 last_write_time, uint16 mount_count,
            uint16 max_mount_count, uint16 lifetime_writes, uint16 first_inode, uint16 inode_size) = _sb.unpack();

        return format("{}\t{}\t{}\n{}\t{}\t{}\t{}\n{}\n{}\t{}\t{}\t{}\t{}\n{}\t{}\t{}\n", file_system_state ? "Y" : "N", errors_behavior ? "Y" : "N",
            file_system_OS_type, inode_count, block_count++, free_inodes, free_blocks--, block_size, created_at, last_mount_time, last_write_time,
            mount_count, max_mount_count, lifetime_writes, first_inode, inode_size);
    }

    function assign_readers(address[] readers) external accept {
        _readers = readers;
        for (address addr: readers)
            ICacheFS(addr).flush_fs_cache{value: 0.02 ton, flag: 1}();
    }

    /* Fully update a file system information on a file system cache device */
    function query_fs_cache() external override view accept {
        ICacheFS(msg.sender).update_fs_cache{value: 0.1 ton, flag: 1}(_sb, _proc, _users, _groups, _inodes);
    }

    function _update_inodes(mapping (uint16 => Inode) inn) internal view {
        for (address addr: _readers)
            ICacheFS(addr).update_fs_cache{value: 0.1 ton, flag: 1}(_sb, _proc, _users, _groups, inn);
    }

    function update_fs_cache(SuperBlock sb, mapping (uint16 => ProcessInfo) processes, mapping (uint16 => UserInfo) users,
                            mapping (uint16 => GroupInfo) groups, mapping (uint16 => Inode) inodes) external accept {
        for ((uint16 i, Inode inode): inodes)
            _inodes[i] = inode;

        _proc = processes;
        _users = users;
        _groups = groups;
        _sb = sb;
    }

    function _update_inodes_set(uint16[] indices) internal view {
        mapping (uint16 => Inode) inn;
        uint count;
        for (uint16 i: indices)
            if (_inodes.exists(i)) {
                inn[i] = _inodes[i];
                count++;
            }
        _update_inodes(inn);
    }

    /* Superblock and index node housekeeping helpers */
    function _claim_inodes(uint i_count, uint b_count) internal {
        uint16 n_inodes = uint16(i_count);
        uint16 n_blocks = uint16(b_count);
        SuperBlock sb = _sb;
        sb.inode_count += n_inodes;
        sb.block_count += n_blocks;
        sb.free_blocks -= n_blocks;
        sb.free_inodes -= n_inodes;
        sb.last_write_time = now;
        sb.lifetime_writes++;
        _sb = sb;
    }

}
