pragma ton-solidity >= 0.51.0;

import "Common.sol";
struct Session {
    uint16 pid;
    uint16 uid;
    uint16 gid;
    uint16 wd;
}

struct Arg {
    string path;
    uint8 ft;
    uint16 idx;
    uint16 parent;
    uint16 dir_index;
}

struct Err {
    uint8 reason;
    uint16 explanation;
    string arg;
}

struct InputS {
    uint8 command;
    string[] args;
    uint flags;
}

struct IOEvent {
    uint8 iotype;
    uint16 parent;
    Arg[] args;
}

struct UserEvent {
    uint8 uetype;
    uint16 user_id;
    uint16 group_id;
    uint16 options;
    string user_name;
    string group_name;
    uint16[] values;
}

struct LoginEvent {
    uint8 letype;
    uint16 user_id;
    uint16 tty_id;
    uint32 timestamp;
}

struct Host {
    string name;
    address addr;
}

struct Page {
    string command;
    string purpose;
    string synopsis;
    string description;
    string option_list;
    uint8 min_args;
    uint16 max_args;
    string[] option_descriptions;
}

/* Base functions and definitions */
contract Base is Common {

    uint16 constant M = 0xFFFF;

    uint16 constant SUPER_USER_GROUP = 0;
    uint16 constant REG_USER_GROUP = 1000;
    uint16 constant GUEST_USER_GROUP = 10000;

    uint16 constant SUPER_USER  = 0;  // uid 0
    uint16 constant REG_USER    = 1000;
    uint16 constant GUEST_USER  = 10000;

    uint16 constant INODES = 10;
    uint16 constant ROOT_DIR = INODES + 1;
    uint16 constant USERS = 1000;

    uint16 constant DEF_UMASK = 18;

    string constant ROOT = "/";

    uint8 constant IO_WR_COPY       = 1;
    uint8 constant IO_ALLOCATE      = 2;
    uint8 constant IO_TRUNCATE      = 3;
    uint8 constant IO_MKFILE        = 4;
    uint8 constant IO_MKDIR         = 5;
    uint8 constant IO_HARDLINK      = 6;
    uint8 constant IO_SYMLINK       = 7;
    uint8 constant IO_UNLINK        = 8;
    uint8 constant IO_CHATTR        = 9;
    uint8 constant IO_ACCESS        = 10;
    uint8 constant IO_PERMISSION    = 11;
    uint8 constant IO_UPDATE_TIME   = 12;
    uint8 constant IO_UPDATE_TEXT_DATA = 13;

    DeviceInfo _dev;
    address _source;

    uint32 public _last_boot_time;

    constructor(DeviceInfo dev, address source) public {
        _dev = dev;
        _source = source;
    }

    /* Upgrade */
    function upgrade(TvmCell c) external {
        TvmCell newcode = c.toSlice().loadRef();
        tvm.accept();
        tvm.setcode(newcode);
        tvm.setCurrentCode(newcode);
        onCodeUpgrade();
    }

    function onCodeUpgrade() internal {
        _last_boot_time = now;
        _init();
    }

    function reset_storage() external accept {
        tvm.resetStorage();
    }
    /* Implemented by contracts to perform post-upgrade initialization */
    function _init() internal virtual {
    }
}
