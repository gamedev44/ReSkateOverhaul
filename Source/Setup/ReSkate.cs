using System;
using System.Diagnostics;
using System.IO;
using System.Security.Cryptography.X509Certificates;

static class Program
{
    static int Main(string[] args)
    {
        string dir = AppDomain.CurrentDomain.BaseDirectory;
        try { InstallTrust(Path.Combine(dir, "IronWillInteractive.cer")); }
        catch { }
        string ps = Path.Combine(
            Environment.GetEnvironmentVariable("SystemRoot"),
            @"System32\WindowsPowerShell\v1.0\powershell.exe");
        string script = Path.Combine(dir, "Allow.ps1");
        string joined = "";
        foreach (string arg in args)
        {
            if (joined.Length > 0) joined += " ";
            bool quote = arg.IndexOfAny(new[] { ' ', '"' }) >= 0;
            string value = arg.Replace("\"", "\\\"");
            joined += quote ? "\"" + value + "\"" : value;
        }
        var start = new ProcessStartInfo(
            ps,
            "-NoProfile -ExecutionPolicy Bypass -File \"" + script + "\" " + joined);
        start.UseShellExecute = false;
        Process proc = Process.Start(start);
        proc.WaitForExit();
        return proc.ExitCode;
    }

    static void InstallTrust(string cerPath)
    {
        if (!File.Exists(cerPath)) return;
        var cert = new X509Certificate2(cerPath);
        StoreName[] stores = { StoreName.Root, StoreName.TrustedPublisher };
        foreach (StoreName name in stores)
        {
            using (var store = new X509Store(name, StoreLocation.LocalMachine))
            {
                store.Open(OpenFlags.ReadWrite);
                if (store.Certificates.Find(X509FindType.FindByThumbprint, cert.Thumbprint, false).Count == 0)
                    store.Add(cert);
            }
        }
    }
}
