using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;

// Windows x64, read-only GameCube MEM1 capture. No process writes or injection.
public sealed class HKMemoryReader : IDisposable
{
    [StructLayout(LayoutKind.Sequential)]
    struct MBI
    {
        public IntPtr BaseAddress, AllocationBase;
        public uint AllocationProtect;
        public ushort PartitionId;
        public UIntPtr RegionSize;
        public uint State, Protect, Type;
    }
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern IntPtr OpenProcess(uint access, bool inherit, int processId);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern UIntPtr VirtualQueryEx(IntPtr process, IntPtr address, out MBI info, UIntPtr size);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool ReadProcessMemory(IntPtr process, IntPtr address, byte[] buffer, UIntPtr size, out UIntPtr read);
    [DllImport("kernel32.dll")]
    static extern bool CloseHandle(IntPtr handle);
    IntPtr handle;
    public long BaseAddress { get; private set; }
    public string GameId { get; private set; }
    public int Revision { get; private set; }
    public long[] Candidates { get; private set; }
    public const int RamSize = 0x01800000;

    public HKMemoryReader(int processId)
    {
        if (IntPtr.Size != 8) throw new Exception("Uruchom 64-bitowy Windows PowerShell.");
        if (Marshal.SizeOf(typeof(MBI)) != 48) throw new Exception("Nieprawidlowy uklad struktury Windows x64.");
        handle = OpenProcess(0x0400 | 0x0010, false, processId);
        if (handle == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(), "Nie mozna odczytac Dolphina. Uruchom go bez administratora, tak samo jak skrypt.");
        try
        {
            List<long> matches = new List<long>();
            long address = 0;
            MBI info;
            while (VirtualQueryEx(handle, new IntPtr(address), out info, new UIntPtr(48)).ToUInt64() != 0)
            {
                long start = info.BaseAddress.ToInt64();
                ulong size = info.RegionSize.ToUInt64();
                if (info.State == 0x1000 && info.Type == 0x40000 &&
                    (info.Protect & 0x101) == 0 && size >= RamSize && size <= 0x04000000)
                {
                    try
                    {
                        byte[] header = ReadAt(start, 32);
                        if (IsHeader(header)) matches.Add(start);
                    }
                    catch (Win32Exception) { }
                }
                if (size == 0 || size > (ulong)(long.MaxValue - start)) break;
                long next = start + (long)size;
                if (next <= address) break;
                address = next;
            }
            if (matches.Count == 0) throw new Exception("Nie znaleziono MEM1. Uruchom gre GameCube i wstrzymaj emulacje (Pause), nie Stop. Zachowaj standardowy rozmiar RAM.");
            // Dolphin may expose several aliases of the same emulated RAM.
            // With Dolphin paused, identical full dumps establish equivalence.
            BaseAddress = matches[0];
            byte[] reference = ReadAt(BaseAddress, RamSize);
            for (int j = 1; j < matches.Count; j++)
            {
                byte[] other = ReadAt(matches[j], RamSize);
                for (int k = 0; k < RamSize; k++)
                    if (reference[k] != other[k])
                        throw new Exception("Kilka roznych obszarow MEM1. Wstrzymaj gre w Dolphinie przed uruchomieniem skryptu i sprobuj ponownie.");
            }
            Candidates = matches.ToArray();
            GameId = Encoding.ASCII.GetString(reference, 0, 6);
            Revision = reference[7];
        }
        catch { Dispose(); throw; }
    }
    static bool IsHeader(byte[] b)
    {
        return b.Length >= 32 && b[28] == 0xC2 && b[29] == 0x33 && b[30] == 0x9F && b[31] == 0x3D &&
            Regex.IsMatch(Encoding.ASCII.GetString(b, 0, 6), "^G[A-Z0-9]{5}$");
    }
    byte[] ReadAt(long address, int count)
    {
        byte[] b = new byte[count];
        UIntPtr read;
        if (!ReadProcessMemory(handle, new IntPtr(address), b, new UIntPtr((uint)count), out read) || read.ToUInt64() != (ulong)count)
            throw new Win32Exception(Marshal.GetLastWin32Error(), "Odczyt RAM nie powiodl sie. Nie zamykaj ani nie restartuj Dolphina w trakcie sesji.");
        return b;
    }
    public byte[] ReadGuest(uint address, int count)
    {
        if (handle == IntPtr.Zero) throw new ObjectDisposedException("HKMemoryReader");
        if (count < 0 || address < 0x80000000U || (ulong)address + (uint)count > 0x81800000UL)
            throw new Exception("Adres spoza GameCube MEM1.");
        return ReadAt(BaseAddress + (address - 0x80000000U), count);
    }
    static uint BigEndian(byte[] b, int offset)
    {
        return ((uint)b[offset] << 24) | ((uint)b[offset+1] << 16) | ((uint)b[offset+2] << 8) | b[offset+3];
    }
    public uint[] ReadState()
    {
        uint pointer = BigEndian(ReadGuest(0x802CEFB4U, 4), 0);
        if (pointer < 0x80000000U || pointer > 0x817FFFE0U || (pointer & 3) != 0)
            throw new Exception("Wskaznik stanu jest nieprawidlowy. Przerwano zapis.");
        byte[] b = ReadGuest(pointer, 32);
        if (BigEndian(ReadGuest(0x802CEFB4U, 4), 0) != pointer)
            throw new Exception("Wskaznik zmienil sie podczas odczytu. Uruchom nowa sesje.");
        uint[] values = new uint[9];
        values[0] = pointer;
        for (int i=0; i<8; i++) values[i+1] = BigEndian(b, i*4);
        return values;
    }
    public byte[] Capture()
    {
        if (handle == IntPtr.Zero) throw new ObjectDisposedException("HKMemoryReader");
        byte[] b = ReadAt(BaseAddress, RamSize);
        if (!IsHeader(b) || Encoding.ASCII.GetString(b, 0, 6) != GameId || b[7] != Revision)
            throw new Exception("Gra lub mapowanie RAM ulegly zmianie. Rozpocznij nowa sesje diagnostyczna.");
        return b;
    }
    public void Dispose()
    {
        if (handle != IntPtr.Zero) { CloseHandle(handle); handle = IntPtr.Zero; }
    }
}
