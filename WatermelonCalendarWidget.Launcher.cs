using System;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

internal static class WatermelonCalendarLauncher
{
    private const string AppUserModelId = "TaliaTerry.WatermelonCalendarWidget";

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern int SetCurrentProcessExplicitAppUserModelID(string appId);

    [STAThread]
    private static int Main(string[] args)
    {
        try
        {
            SetCurrentProcessExplicitAppUserModelID(AppUserModelId);

            string appDirectory = AppDomain.CurrentDomain.BaseDirectory;
            string scriptPath = Path.Combine(appDirectory, "WatermelonCalendarWidget.ps1");
            if (!File.Exists(scriptPath))
            {
                MessageBox.Show(
                    "The Watermelon Calendar program file could not be found. Please run Install.cmd again.",
                    "Watermelon Calendar Widget",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
                return 1;
            }

            InitialSessionState initialSessionState = InitialSessionState.CreateDefault();
            initialSessionState.ExecutionPolicy = Microsoft.PowerShell.ExecutionPolicy.Bypass;

            using (Runspace runspace = RunspaceFactory.CreateRunspace(initialSessionState))
            {
                runspace.ApartmentState = ApartmentState.STA;
                runspace.ThreadOptions = PSThreadOptions.UseCurrentThread;
                runspace.Open();

                using (PowerShell powerShell = PowerShell.Create())
                {
                    powerShell.Runspace = runspace;
                    powerShell.AddCommand(scriptPath);
                    foreach (string argument in args)
                    {
                        if (string.Equals(argument, "--start-minimized", StringComparison.OrdinalIgnoreCase))
                        {
                            powerShell.AddParameter("StartMinimized");
                        }
                    }

                    powerShell.Invoke();
                    if (powerShell.HadErrors)
                    {
                        string message = powerShell.Streams.Error.Count > 0
                            ? powerShell.Streams.Error[0].ToString()
                            : "The calendar stopped because of an unexpected error.";
                        MessageBox.Show(message, "Watermelon Calendar Widget", MessageBoxButtons.OK, MessageBoxIcon.Error);
                        return 1;
                    }
                }
            }

            return 0;
        }
        catch (Exception exception)
        {
            MessageBox.Show(
                exception.Message,
                "Watermelon Calendar Widget",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            return 1;
        }
    }
}
