using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;

namespace Whyun.Usage.Windows
{
    internal static class CliCommand
    {
        public static ProcessStartInfo Create(string executable, string arguments)
        {
            string path = Resolve(executable);
            string extension = Path.GetExtension(path).ToLowerInvariant();
            var info = new ProcessStartInfo
            {
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardInput = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                WorkingDirectory = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            };

            if (extension == ".cmd" || extension == ".bat")
            {
                info.FileName = Path.Combine(Environment.SystemDirectory, "cmd.exe");
                info.Arguments = "/d /s /c \"\"" + path + "\" " + arguments + "\"";
            }
            else if (extension == ".ps1")
            {
                info.FileName = Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe");
                info.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"" + path + "\" " + arguments;
            }
            else
            {
                info.FileName = path;
                info.Arguments = arguments;
            }

            return info;
        }

        private static string Resolve(string executable)
        {
            if (Path.IsPathRooted(executable) && File.Exists(executable))
            {
                return executable;
            }

            var directories = new List<string>();
            string pathValue = Environment.GetEnvironmentVariable("PATH") ?? string.Empty;
            directories.AddRange(pathValue.Split(new[] { Path.PathSeparator }, StringSplitOptions.RemoveEmptyEntries));

            string appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            if (!string.IsNullOrWhiteSpace(appData))
            {
                directories.Add(Path.Combine(appData, "npm"));
            }

            string[] extensions = { ".exe", ".cmd", ".bat", ".ps1", string.Empty };
            foreach (string directoryValue in directories)
            {
                string directory = directoryValue.Trim().Trim('"');
                foreach (string extension in extensions)
                {
                    string candidate = Path.Combine(directory, executable + extension);
                    if (File.Exists(candidate))
                    {
                        return candidate;
                    }
                }
            }

            throw new FileNotFoundException(executable + " CLI is not installed or is not on PATH.");
        }
    }
}
