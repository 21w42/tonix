pragma ton-solidity >= 0.51.0;

import "Base.sol";
import "Format.sol";

struct Inode {
    uint16 mode;
    uint16 owner_id;
    uint16 group_id;
    uint32 file_size;
    uint16 n_links;
    uint32 modified_at;
    uint32 last_modified;
    string file_name;
    string[] text_data;
}

struct SuperBlock {
    bool file_system_state;
    bool errors_behavior;
    string file_system_OS_type;
    uint16 inode_count;
    uint16 block_count;
    uint16 free_inodes;
    uint16 free_blocks;
    uint16 block_size;
    uint32 created_at;
    uint32 last_mount_time;
    uint32 last_write_time;
    uint16 mount_count;
    uint16 max_mount_count;
    uint16 lifetime_writes;
    uint16 first_inode;
    uint16 inode_size;
}

struct MountInfo {
    uint8 source_dev_id;
    uint16 source_id;
    uint16 target_mount_point;
    string target_path;
    uint16 options;
}

struct FileMapS {
    uint16 storage_type;
    uint16 start;
    uint16 count;
}

struct FileS {
    uint16 mode;
    uint16 inode;
    uint16 state;
    uint16 bc;
    uint16 n_blk;
    uint32 pos;
    uint32 fize;
    string name;
}

struct ProcessInfo {
    uint16 owner_id;
    uint16 self_id;
    uint16 umask;
    mapping (uint16 => FileS) fd_table;
    string cwd;
}

struct UserInfo {
    uint16 gid;
    string user_name;
    string primary_group;
}

struct GroupInfo {
    string group_name;
    bool is_system;
}

struct Login {
    uint16 user_id;
    uint16 tty_id;
    uint16 process_id;
    uint32 login_time;
}

struct TTY {
    uint8 device_id;
    uint16 user_id;
    uint16 login_id;
}

struct TextDataFile {
    uint8 file_type;
    string file_name;
    string[] contents;
}

/* Base contract to work with index nodes */
contract Internal is Base, Format {

    uint16 constant S_IXOTH = 1 << 0;
    uint16 constant S_IWOTH = 1 << 1;
    uint16 constant S_IROTH = 1 << 2;
    uint16 constant S_IRWXO = S_IROTH + S_IWOTH + S_IXOTH;

    uint16 constant S_IXGRP = 1 << 3;
    uint16 constant S_IWGRP = 1 << 4;
    uint16 constant S_IRGRP = 1 << 5;
    uint16 constant S_IRWXG = S_IRGRP + S_IWGRP + S_IXGRP;

    uint16 constant S_IXUSR = 1 << 6;
    uint16 constant S_IWUSR = 1 << 7;
    uint16 constant S_IRUSR = 1 << 8;
    uint16 constant S_IRWXU = S_IRUSR + S_IWUSR + S_IXUSR;

    uint16 constant S_ISVTX = 1 << 9;  //   sticky bit
    uint16 constant S_ISGID = 1 << 10; //   set-group-ID bit
    uint16 constant S_ISUID = 1 << 11; //   set-user-ID bit

    uint16 constant S_IFIFO = 1 << 12;
    uint16 constant S_IFCHR = 1 << 13;
    uint16 constant S_IFDIR = 1 << 14;
    uint16 constant S_IFBLK = S_IFDIR + S_IFCHR;
    uint16 constant S_IFREG = 1 << 15;
    uint16 constant S_IFLNK = S_IFREG + S_IFCHR;
    uint16 constant S_IFSOCK = S_IFREG + S_IFDIR;
    uint16 constant S_IFMT  = 0xF000; //   bit mask for the file type bit field

    uint16 constant DEF_REG_FILE_MODE   = S_IFREG + S_IRUSR + S_IWUSR + S_IRGRP + S_IROTH;
    uint16 constant DEF_DIR_MODE        = S_IFDIR + S_IRWXU + S_IRGRP + S_IXGRP + S_IROTH + S_IXOTH;
    uint16 constant DEF_SYMLINK_MODE    = S_IFLNK + S_IRWXU + S_IRWXG + S_IRWXO;
    uint16 constant DEF_BLOCK_DEV_MODE  = S_IFBLK + S_IRUSR + S_IWUSR;
    uint16 constant DEF_CHAR_DEV_MODE   = S_IFCHR + S_IRUSR + S_IWUSR;
    uint16 constant DEF_FIFO_MODE       = S_IFIFO + S_IRUSR + S_IWUSR + S_IRGRP + S_IROTH;
    uint16 constant DEF_SOCK_MODE       = S_IFSOCK + S_IRWXU + S_IRGRP + S_IXGRP + S_IROTH + S_IXOTH;

    uint8 constant FT_UNKNOWN   = 0;
    uint8 constant FT_REG_FILE  = 1;
    uint8 constant FT_DIR       = 2;
    uint8 constant FT_CHRDEV    = 3;
    uint8 constant FT_BLKDEV    = 4;
    uint8 constant FT_FIFO      = 5;
    uint8 constant FT_SOCK      = 6;
    uint8 constant FT_SYMLINK   = 7;
    uint8 constant FT_LAST      = FT_SYMLINK;

    uint16 constant MOUNT_NONE          = 0;
    uint16 constant MOUNT_DIR           = 1;
    uint16 constant MOUNT_OVERLAY       = 4;
    uint16 constant QUERY_FS_CACHE      = 5;

    uint8 constant UA_ADD_USER          = 1;
    uint8 constant UA_ADD_GROUP         = 2;
    uint8 constant UA_DELETE_USER       = 3;
    uint8 constant UA_DELETE_GROUP      = 4;
    uint8 constant UA_UPDATE_USER       = 5;
    uint8 constant UA_UPDATE_GROUP      = 6;
    uint8 constant UA_RENAME_GROUP      = 7;
    uint8 constant UA_CHANGE_GROUP_ID   = 8;

    uint16 constant UAO_SYSTEM              = 16;
    uint16 constant UAO_CREATE_HOME_DIR     = 32;
    uint16 constant UAO_CREATE_USER_GROUP   = 64;
    uint16 constant UAO_ADD_SUPP_GROUPS     = 128;
    uint16 constant UAO_REMOVE_HOME_DIR     = 1024;
    uint16 constant UAO_REMOVE_EMPTY_GROUPS = 2048;

    uint8 constant AE_LOGIN         = 1;
    uint8 constant AE_LOGOUT        = 2;
    uint8 constant AE_SHUTDOWN      = 3;

    constructor(DeviceInfo dev, address source) Base (dev, source) public {
    }

    /* File system helpers */
    function _dump_fs(uint8 level, SuperBlock sb, mapping (uint16 => Inode) inodes) internal pure returns (string out) {
        (bool file_system_state, bool errors_behavior, string file_system_OS_type, uint16 inode_count, uint16 block_count, uint16 free_inodes,
            uint16 free_blocks, uint16 block_size, uint32 created_at, uint32 last_mount_time, uint32 last_write_time, uint16 mount_count,
            uint16 max_mount_count, uint16 lifetime_writes, uint16 first_inode, uint16 inode_size) = sb.unpack();
        out = format("{} IC {} BC {} FI {} FB {} BS {} MC {} MMC {} WR {} FI {} IS {} FSS {} EB {}\n",
            file_system_OS_type, inode_count, block_count, free_inodes, free_blocks, block_size,
            mount_count, max_mount_count, lifetime_writes, first_inode, inode_size, file_system_state ? "Y" : "N", errors_behavior ? "Y" : "N");
        out.append(format("CT {} LMT {} LWT {}\n", _ts(created_at), _ts(last_mount_time), _ts(last_write_time)));

        for ((uint16 i, Inode ino): inodes) {
            (uint16 mode, uint16 owner_id, uint16 group_id, uint32 file_size, uint16 n_links, , , string file_name, string[] text_data) = ino.unpack();
            out.append(format("I {} {} PM {} O {} G {} SZ {} NL {}\n", i, file_name, mode, owner_id, group_id, file_size, n_links));
            if (level > 0 && ((mode & S_IFMT) == S_IFDIR || (mode & S_IFMT) == S_IFLNK) || level > 1)
                for (string s: text_data)
                    out.append(s + "\n");
        }
    }

    /* Directory entry helpers */
    function _add_dir_entry(Inode dir, uint16 ino, string file_name, uint8 file_type) internal pure returns (Inode) {
        string dirent = _dir_entry_line(ino, file_name, file_type);
        dir.text_data.push(dirent);
        dir.file_size += uint32(dirent.byteLength());
        dir.n_links++;
        return dir;
    }

    function _read_dir_entry(string s) internal pure returns (string file_name, uint16 inode, uint8 file_type) {
        file_type = _file_type(s.substr(0, 1));
        uint p = _strchr(s, "\t");
        file_name = s.substr(1, p - 2);
        (uint inode_n, bool success) = stoi(s.substr(p, s.byteLength() - p));
        if (success)
            inode = uint16(inode_n);
    }

    function _dir_entry_line(uint16 index, string file_name, uint8 file_type) internal pure returns (string) {
        return _file_type_sign(file_type) + file_name + format("\t{}", index);
    }

    /* Index node, file and directory entry types helpers */
    function _get_device_version(string[] text) internal pure returns (string major, string minor) {
        major = _element_at(1, 1, text, "\t");
        minor = _element_at(1, 2, text, "\t");
    }

    function _permissions(uint16 p) internal pure returns (string) {
        return _inode_mode_sign(p) + _p_octet(p >> 6 & 0x0007) + _p_octet(p >> 3 & 0x0007) + _p_octet(p & 0x0007);
    }

    function _p_octet(uint16 p) internal pure returns (string out) {
        out = ((p & 4) > 0) ? "r" : "-";
        out.append(((p & 2) > 0) ? "w" : "-");
        out.append(((p & 1) > 0) ? "x" : "-");
    }

    function _inode_mode_sign(uint16 mode) internal pure returns (string) {
        if ((mode & S_IFMT) == S_IFBLK)  return "b";
        if ((mode & S_IFMT) == S_IFCHR)  return "c";
        if ((mode & S_IFMT) == S_IFREG)  return "-";
        if ((mode & S_IFMT) == S_IFDIR)  return "d";
        if ((mode & S_IFMT) == S_IFLNK)  return "l";
        if ((mode & S_IFMT) == S_IFSOCK) return "s";
        if ((mode & S_IFMT) == S_IFIFO)  return "p";
    }

    function _mode_to_file_type(uint16 mode) internal pure returns (uint8) {
        if ((mode & S_IFMT) == S_IFBLK)  return FT_BLKDEV;
        if ((mode & S_IFMT) == S_IFCHR)  return FT_CHRDEV;
        if ((mode & S_IFMT) == S_IFREG)  return FT_REG_FILE;
        if ((mode & S_IFMT) == S_IFDIR)  return FT_DIR;
        if ((mode & S_IFMT) == S_IFLNK)  return FT_SYMLINK;
        if ((mode & S_IFMT) == S_IFSOCK) return FT_SOCK;
        if ((mode & S_IFMT) == S_IFIFO)  return FT_FIFO;
        return FT_UNKNOWN;
    }

    function _file_type_sign(uint8 ft) internal pure returns (string) {
        if (ft == FT_BLKDEV)    return "b";
        if (ft == FT_CHRDEV)    return "c";
        if (ft == FT_REG_FILE)  return "-";
        if (ft == FT_DIR)       return "d";
        if (ft == FT_SYMLINK)   return "l";
        if (ft == FT_SOCK)      return "s";
        if (ft == FT_FIFO)      return "p";
        return "?";
    }

    function _file_type(string s) internal pure returns (uint8) {
        if (s == "b") return FT_BLKDEV;
        if (s == "c") return FT_CHRDEV;
        if (s == "-") return FT_REG_FILE;
        if (s == "d") return FT_DIR;
        if (s == "l") return FT_SYMLINK;
        if (s == "s") return FT_SOCK;
        if (s == "p") return FT_FIFO;
        return FT_UNKNOWN;
    }

    function _file_type_description(uint16 mode) internal pure returns (string) {
        if ((mode & S_IFMT) == S_IFBLK)  return "block special";
        if ((mode & S_IFMT) == S_IFCHR)  return "character special";
        if ((mode & S_IFMT) == S_IFREG)  return "regular";
        if ((mode & S_IFMT) == S_IFDIR)  return "directory";
        if ((mode & S_IFMT) == S_IFLNK)  return "symbolic link";
        if ((mode & S_IFMT) == S_IFSOCK) return "socket";
        if ((mode & S_IFMT) == S_IFIFO)  return "fifo";
        return "unknown";
    }

    function _get_def_mode(uint8 file_type) internal pure returns (uint16) {
        if (file_type == FT_REG_FILE) return DEF_REG_FILE_MODE;
        if (file_type == FT_DIR) return DEF_DIR_MODE;
        if (file_type == FT_SYMLINK) return DEF_SYMLINK_MODE;
        if (file_type == FT_BLKDEV) return DEF_BLOCK_DEV_MODE;
        if (file_type == FT_CHRDEV) return DEF_CHAR_DEV_MODE;
        if (file_type == FT_FIFO) return DEF_FIFO_MODE;
        if (file_type == FT_SOCK) return DEF_SOCK_MODE;
    }

    function _get_any_node(uint8 ft, uint16 owner, uint16 group, string file_name, string[] text_data) internal pure returns (Inode) {
        if (ft > FT_UNKNOWN && ft <= FT_LAST) {
            uint file_size;
            for (string s: text_data)
                file_size += s.byteLength();
            return Inode(_get_def_mode(ft), owner, group, uint32(file_size), ft == FT_DIR ? 2 : 1, now, now, file_name, text_data);
        }
    }

    /* Getting an index node of a particular type */
    function _get_file_node(uint16 owner, uint16 group, string file_name, string[] text_data) internal pure returns (Inode) {
        uint file_size;
        for (string s: text_data)
            file_size += s.byteLength();
        return Inode(DEF_REG_FILE_MODE, owner, group, uint32(file_size), 1, now, now, file_name, text_data);
    }

    function _get_dots(uint16 this_dir, uint16 parent_dir) internal pure returns (string[]) {
        return [format("d.\t{}", this_dir), format("d..\t{}", parent_dir)];
    }

    function _get_dir_node(uint16 this_dir, uint16 parent_dir, uint16 owner, uint16 group, string dir_name) internal pure returns (Inode) {
//        return _get_any_node(FT_DIR, owner, group, dir_name, [format("d.\t{}", this_dir), format("d..\t{}", parent_dir)]);
        return _get_any_node(FT_DIR, owner, group, dir_name, _get_dots(this_dir, parent_dir));
    }

    function _get_symlink_node(uint16 owner, uint16 group, string file_name, string target_dirent) internal pure returns (Inode) {
        return _get_any_node(FT_SYMLINK, owner, group, file_name, [target_dirent]);
    }
}
