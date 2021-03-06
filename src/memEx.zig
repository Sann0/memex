const std = @import("std");
const mem = std.mem;

usingnamespace std.os.windows;
usingnamespace @import("winapi.zig");

pub const Process = struct {
    name: []const u8,
    handle: HANDLE,
    pid: u32,
    baseaddr: usize,
    basesize: u32,

    pub fn open(self: *Process, processName: []const u8) !void {
        var pidArray: [1024]u32 = undefined;
        var r: DWORD = undefined;
        var me: MODULEENTRY32 = undefined;
        
        me.dwSize = @sizeOf(MODULEENTRY32);
        _ = EnumProcesses(&pidArray[0], 1024, &r); // Shouldn't fail.

        for (pidArray[0..r/4]) |pid| {
            var snap = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32, pid);
            defer CloseHandle(snap);

            if (Module32First(snap, &me) == 1) {
                var binName = me.szModule[0..mem.indexOfScalar(u8, &me.szModule, 0).?];

                if (mem.eql(u8, processName, binName)) {
                    self.handle = OpenProcess(SYNCHRONIZE | STANDARD_RIGHTS_REQUIRED | 0xffff, 0, me.th32ProcessID);
                    self.name = binName;
                    self.baseaddr = @ptrToInt(me.modBaseAddr);
                    self.basesize = me.modBaseSize;
                    self.pid = me.th32ProcessID;
                    return;
                }
            }
        }
        return error.ProcessNotFound;
    }

    pub fn moduleAddress(self: *Process, moduleName: []const u8) ?usize {
        var snap = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32, self.pid);
        defer CloseHandle(snap);

        var me: MODULEENTRY32 = undefined;
        me.dwSize = @sizeOf(MODULEENTRY32);

        if (Module32First(snap, &me) == 1) {
            while (Module32Next(snap, &me) != 0) {
                var modName = me.szModule[0..mem.indexOfScalar(u8, &me.szModule, 0).?];
                if (mem.eql(u8, moduleName, modName)) return @ptrToInt(me.modBaseAddr);
            }
        }
        return null;
    }

    pub fn read(self: *Process, address: usize, comptime T: type) !T {
        var buffer: [@sizeOf(T)]u8 = undefined;
        var numRead: usize = undefined;

        if (ReadProcessMemory(self.handle, @intToPtr(LPCVOID, address), &buffer, @sizeOf(T), &numRead) != 1)
            return error.ReadFailed;
        return @bitCast(T, buffer);
    }

    pub fn write(self: *Process, address: usize, data: var) !void {
        var tmp: usize = undefined;
        if (WriteProcessMemory(self.handle, @intToPtr(LPCVOID, address), &data, @sizeOf(@TypeOf(data)), null) != 1)
            return error.WriteFailed;
    }

    pub fn dmaAddr(self: *Process, baseAddress: usize, offsets: var) !usize {
        var res = try self.read(baseAddress, usize);
        while (offsets) |o| res = self.read(res + o, usize);
        return res;
    }

    pub fn nopCode(self: *Process, address: usize, length: usize) !void {
        var i: usize = 0;
        while (i <= length): (i += 1)
            self.write(address + (i - 1), u8(0x90));
    }

    pub fn close(self: *Process) void {
        CloseHandle(self.handle);
    }
};