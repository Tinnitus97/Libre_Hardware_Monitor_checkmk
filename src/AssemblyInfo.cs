// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/.

using System.ComponentModel;
using System.Management.Instrumentation;

// Same WMI namespace as the original OpenHardwareMonitorCLI.exe.
// The Checkmk Windows agent queries "SELECT * FROM Sensor" in Root\OpenHardwareMonitor.
[assembly: Instrumented("root/OpenHardwareMonitor")]

/// <summary>
/// Allows the WMI schema to be registered up-front with InstallUtil.exe
/// (optional; the schema is also registered automatically on first start as administrator/SYSTEM).
/// </summary>
[RunInstaller(true)]
public class InstanceInstaller : DefaultManagementProjectInstaller
{
}
