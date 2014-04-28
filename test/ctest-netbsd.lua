-- generate C test file to check ABI

package.path = "./?.lua;"

local abi = require "syscall.abi"

local S

if abi.os == "netbsd" then -- testing natively
  S = require "syscall"
else -- test using rump
  S = require "syscall.rump.init".init()
end

local version = require "syscall.netbsd.version".version

local abi = S.abi
local types = S.types
local t, ctypes, s = types.t, types.ctypes, types.s
local c = S.c

for k, v in pairs(ctypes) do
  local kk = string.gsub(k, "_netbsd_", "")
  if kk ~= k then ctypes[kk], ctypes[k] = v, nil end
end
 
local ffi = require "ffi"

local reflect = require "include.ffi-reflect.reflect"

-- internal only
c.errornames = nil

-- fixups
c.STD = nil
c.EXIT = nil

-- TODO this should be in system headers surely? (F_ULOCK, F_LOCK etc)
c.LOCKF = nil

for k, v in pairs(c.IOCTL) do if type(v) == "table" then c.IOCTL[k] = v.number end end

c.AF.DECnet = c.AF.DECNET
c.AF.DECNET = nil

c.R_OK = c.OK.R
c.W_OK = c.OK.W
c.F_OK = c.OK.F
c.X_OK = c.OK.X
c.OK = nil

c.SIGACT = nil -- TODO cast correctly instead, giving warning
c.CHFLAGS.NODUMP = nil -- alias
c.CHFLAGS.IMMUTABLE = nil -- alias
c.CHFLAGS.APPEND = nil -- alias
c.CHFLAGS.OPAQUE = nil -- alias

c.KTRFLAG = {DESCEND = c.KTROP.DESCEND}
c.KTROP.DESCEND = nil

c.KTRFAC.V0 = nil -- no underscore and lower case
c.KTRFAC.V1 = nil
c.KTRFAC.V2 = nil

c.W.WCLONE = nil -- underscore in name, changed
c.W.WALL   = nil -- underscore in name, changed

-- the #define and the name used are different, very odd
c.KERN_PIPE.MAXLOANKVASZ = nil

-- v7 only
c.CTLFLAG.UNSIGNED = nil

-- complex rename
for k, v in pairs(c.FSYNC) do
  c.FSYNC['F' .. k .. 'SYNC'] = v
  c.FSYNC[k] = nil
end

-- these are Linux names TODO are there actually BSD names?
ctypes["struct ethhdr"] = nil
ctypes["struct iphdr"] = nil
ctypes["struct udphdr"] = nil

-- compat type may be missing
ctypes["struct compat_60_ptmget"] = nil

-- not all syscalls always defined, some conditional, some very new
c.SYS.compat_10_oshmsys = nil
c.SYS.compat_10_omsgsys = nil
c.SYS.compat_10_osemsys = nil
c.SYS.compat_60_sa_enable = nil
c.SYS.compat_60_sa_stacks = nil
c.SYS.compat_60_sa_setconcurrency = nil
c.SYS.compat_60_sa_preempt = nil
c.SYS.compat_60_sa_yield = nil
c.SYS.compat_60_sa_register = nil
c.SYS.___lwp_park60 = nil
c.SYS.sendmmsg = nil
c.SYS.recvmmsg = nil
c.SYS.compat_60__lwp_park = nil
c.SYS.clock_nanosleep = nil

-- not really in earlier versions
if version < 7 then
  ctypes["struct mmsghdr"] = nil
end

print [[
/* this code is generated by ctest-netbsd.lua */

#define _BSD_SOURCE
#define _NETBSD_SOURCE
#define _INCOMPLETE_XOPEN_C063

#include <stddef.h>
#include <stdio.h>

#include <sys/sched.h>
#include <sys/termios.h>
#include <sys/unistd.h>
#include <sys/dirent.h>
#include <sys/time.h>
#include <sys/poll.h>
#include <sys/signal.h>
#include <sys/fcntl.h>
#include <sys/errno.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/socket.h>
#include <sys/utsname.h>
#include <sys/resource.h>
#include <sys/un.h>
#include <sys/mman.h>
#include <sys/xattr.h>
#include <sys/mount.h>
#include <sys/uio.h>
#include <sys/wait.h>
#include <sys/ioctl.h>
#include <sys/reboot.h>
#include <sys/module.h>
#include <sys/syscall.h>
#include <sys/sysctl.h>
#include <sys/statvfs.h>
#include <sys/event.h>
#include <sys/ktrace.h>
#include <sys/extattr.h>
#include <sys/pipe.h>
#include <sys/aio.h>
#include <net/if.h>
#include <net/if_ether.h>
#include <net/if_bridgevar.h>
#include <net/route.h>
#include <net/bpf.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <netinet6/in6.h>
#include <netinet6/in6_var.h>
#include <netinet6/nd6.h>
#include <ufs/ufs/ufsmount.h>
#include <fs/ptyfs/ptyfs.h>
#include <fs/tmpfs/tmpfs_args.h>
#include <miscfs/procfs/procfs.h>

int ret = 0;

void sassert(int a, int b, char *n) {
  if (a != b) {
    printf("error with %s: %d (0x%x) != %d (0x%x)\n", n, a, a, b, b);
    ret = 1;
  }
}

void sassert_u64(unsigned long long a, unsigned long long b, char *n) {
  if (a != b) {
    printf("error with %s: %llu (0x%llx) != %llu (0x%llx)\n", n, (unsigned long long)a, (unsigned long long)a, (unsigned long long)b, (unsigned long long)b);
    ret = 1;
  }
}

int main(int argc, char **argv) {
]]

local ignore_offsets = {
  sig = "true", -- sigset_t renamed TODO rename back
}

-- iterate over S.ctypes
for k, v in pairs(ctypes) do
  print("sassert(sizeof(" .. k .. "), " .. ffi.sizeof(v) .. ', "' .. k .. '");')
  -- check offset of struct fields
  local refct = reflect.typeof(v)
  if refct.what == "struct" then
    for r in refct:members() do
      local name = r.name
      -- bit hacky - TODO fix these issues
      if ignore_offsets[name] then name = nil end
      if name then
        print("sassert(offsetof(" .. k .. "," .. name .. "), " .. ffi.offsetof(v, name) .. ', " offset of ' .. name .. ' in ' .. k .. '");')
      end
    end
  end
end

-- test all the constants

-- renamed ones
local nm = {
  E = "E",
  SIG = "SIG",
  STD = "STD",
  MODE = "S_I",
  MSYNC = "MS_",
  W = "W",
  POLL = "POLL",
  S_I = "S_I",
  LFLAG = "",
  IFLAG = "",
  OFLAG = "",
  CFLAG = "",
  CC = "",
  IOCTL = "",
  B = "B",
  AT_FDCWD = "AT_",
  FCNTL_LOCK = "F_",
  LOCKF = "F_",
  SIGACT = "SIG_",
  UMOUNT = "MNT_",
  SIGPM = "SIG_",
  OPIPE = "O_",
  MSYNC = "MS_",
  CHFLAGS = "",
  PC = "_PC_",
  FSYNC = "",
  TCSA = "TCSA",
  TCFLUSH = "TC",
  TCFLOW = "TC",
  VFSMNT = "MNT_",
  BRDG = "BRDG",
}

for k, v in pairs(c) do
  if type(v) == "number" then
    print("sassert(" .. k .. ", " .. v .. ', "' .. k .. '");')
  elseif type(v) == "table" then
    for k2, v2 in pairs(v) do
      local name = nm[k] or k .. "_"
      if type(v2) ~= "function" then
        if type(v2) == "cdata" and ffi.sizeof(v2) == 8 then
         print("sassert_u64(" .. name .. k2 .. ", " .. tostring(v2)  .. ', "' .. name .. k2 .. '");')
        else
         print("sassert(" .. name .. k2 .. ", " .. tostring(tonumber(v2))  .. ', "' .. name .. k2 .. '");')
        end
      end
    end
  end
end

print [[
return ret;
}
]]

