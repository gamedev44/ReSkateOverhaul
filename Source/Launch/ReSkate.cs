using System;
using System.Diagnostics;
using System.IO;
using System.Text.RegularExpressions;

static class Program
{
    static int Main(string[] args)
    {
        string root = AppDomain.CurrentDomain.BaseDirectory;
        string script = Path.Combine(root, "Source", "Launch", "Select.ps1");
        if (!File.Exists(script)) return 1;
        string ps = Path.Combine(
            Environment.GetEnvironmentVariable("SystemRoot"),
            @"System32\WindowsPowerShell\v1.0\powershell.exe");
        string drive = "";
        if (args.Length > 0 && Regex.IsMatch(args[0], "^[A-Za-z]$"))
            drive = " -Drive " + args[0];
        var start = new ProcessStartInfo(
            ps,
            "-NoProfile -Sta -WindowStyle Hidden -ExecutionPolicy Bypass -File \"" + script + "\"" + drive);
        start.UseShellExecute = false;
        start.WorkingDirectory = root;
        Process.Start(start);
        return 0;
    }
}
