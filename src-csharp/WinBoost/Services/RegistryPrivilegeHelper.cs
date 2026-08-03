using System.Security.AccessControl;
using System.Security.Principal;
using Microsoft.Win32;

namespace WinBoost.Services;

// ============================================================
// Fix: la optimizacion fallaba con "acceso denegado" en claves HKLM cuya ACL
// de fabrica no le da permiso de escritura ni siquiera al grupo Administradores
// (ej. SystemProfile\Tasks\Games en instalaciones limpias de Windows 10/11).
// Punto unico usado por OptimizationService y TuningService antes de escribir
// HKLM protegido: intenta escribir normal y, solo si falla por ACL, toma
// ownership + otorga FullControl a Administradores y reintenta.
// ============================================================
internal static class RegistryPrivilegeHelper
{
    // Evita repetir el arreglo de ACL sobre la misma clave en la misma corrida.
    private static readonly HashSet<string> _fixedKeys = new(StringComparer.OrdinalIgnoreCase);

    internal static RegistryKey? OpenWritable(RegistryHive hive, string subKey)
    {
        using RegistryKey baseKey = RegistryKey.OpenBaseKey(hive, RegistryView.Default);
        try
        {
            return baseKey.CreateSubKey(subKey, writable: true);
        }
        catch (UnauthorizedAccessException) { }
        catch (System.Security.SecurityException) { }

        EnsureWritableAcl(hive, subKey);
        return baseKey.CreateSubKey(subKey, writable: true);
    }

    // Toma ownership del subkey (si ya existe) y agrega FullControl para
    // BUILTIN\Administrators. Si el subkey no existe todavia, no hace falta:
    // CreateSubKey lo crea sin heredar la ACL restrictiva del padre.
    internal static void EnsureWritableAcl(RegistryHive hive, string subKey)
    {
        string cacheKey = $"{hive}:{subKey}";
        if (!_fixedKeys.Add(cacheKey)) return;

        NativeMethods.EnablePrivilege("SeTakeOwnershipPrivilege");
        NativeMethods.EnablePrivilege("SeRestorePrivilege");

        var admins = new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null);
        using RegistryKey baseKey = RegistryKey.OpenBaseKey(hive, RegistryView.Default);

        try
        {
            using (var key = baseKey.OpenSubKey(subKey, RegistryKeyPermissionCheck.ReadWriteSubTree, RegistryRights.TakeOwnership))
            {
                if (key is null) return;
                var sec = key.GetAccessControl(AccessControlSections.Owner);
                sec.SetOwner(admins);
                key.SetAccessControl(sec);
            }
            using (var key = baseKey.OpenSubKey(subKey, RegistryKeyPermissionCheck.ReadWriteSubTree, RegistryRights.ChangePermissions))
            {
                if (key is null) return;
                var sec = key.GetAccessControl();
                sec.AddAccessRule(new RegistryAccessRule(admins, RegistryRights.FullControl, AccessControlType.Allow));
                key.SetAccessControl(sec);
            }
        }
        catch (Exception ex)
        {
            App.Logger?.Log($"No se pudo tomar ownership de {hive}\\{subKey}: {ex.Message}", "err");
        }
    }
}
