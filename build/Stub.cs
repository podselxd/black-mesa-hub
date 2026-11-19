using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;

// Lanzador minimo. Lleva el Hub dentro y lo copia a %LOCALAPPDATA%\BlackMesaHub.
// Si ya hay una version instalada igual o mas nueva, no se pisa nada (se conservan los ajustes).
class BlackMesaHubStub
{
    static Version ReadVersion(string text)
    {
        Version v;
        return Version.TryParse((text ?? "").Trim(), out v) ? v : null;
    }

    static void Main()
    {
        string root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "BlackMesaHub");
        Directory.CreateDirectory(root);

        Assembly asm = Assembly.GetExecutingAssembly();

        Version embedded = null;
        using (Stream vs = asm.GetManifestResourceStream("version.txt"))
        {
            if (vs != null) using (StreamReader r = new StreamReader(vs)) embedded = ReadVersion(r.ReadToEnd());
        }
        Version installed = null;
        string installedFile = Path.Combine(root, "version.txt");
        if (File.Exists(installedFile)) installed = ReadVersion(File.ReadAllText(installedFile));

        bool newer = installed == null || embedded == null || embedded > installed;

        foreach (string name in asm.GetManifestResourceNames())
        {
            string dest = Path.Combine(root, name.Replace('/', Path.DirectorySeparatorChar));
            if (!newer && File.Exists(dest)) continue;
            Directory.CreateDirectory(Path.GetDirectoryName(dest));
            using (Stream s = asm.GetManifestResourceStream(name))
            using (FileStream f = new FileStream(dest, FileMode.Create, FileAccess.Write))
                s.CopyTo(f);
        }

        ProcessStartInfo psi = new ProcessStartInfo();
        psi.FileName = "powershell.exe";
        psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + Path.Combine(root, "hub.ps1") + "\"";
        psi.WorkingDirectory = root;
        psi.UseShellExecute = false;
        psi.CreateNoWindow = true;
        Process.Start(psi);
    }
}
