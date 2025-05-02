
$DCVMName = "DC-Test"
$ADCVMName = "ADC-Test"
$TargetCluster = Get-Cluster -Name "RAD"
$Datastore = "Datastore-trunas"
$SourceVMTemplate = Get-Template -Name "WinSer19-Template"
$SourceCustomSpec = Get-OSCustomizationSpec -Name "Spec-DC"
$ASourceCustomSpec = Get-OSCustomizationSpec -Name "Spec-ADC"
$DCNetworkSettings = 'netsh interface ipv4 set address "Ethernet0" static 172.16.4.254 255.255.255.0 172.16.4.1'
$DCLocalUser = "Administrator"
$DCLocalPWord = ConvertTo-SecureString -String "P@ssw0rd" -AsPlainText -Force
$DCLocalCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $DCLocalUser, $DCLocalPWord
$InstallADRole = 'Install-WindowsFeature -Name "AD-Domain-Services" -IncludeManagementTools -Restart:$false'
$InstallDNSRole = 'Install-WindowsFeature -Name "DNS" -IncludeManagementTools -Restart:$false'
$ConfigureNewDomain = 'Write-Verbose -Message "Configuring Active Directory" -Verbose;
                       $DomainMode = "Win2012R2";
                       $ForestMode = "Win2012R2";
                       $DomainName = "TestDomain.lcl";
                       $DSRMPWord = ConvertTo-SecureString -String "Password01" -AsPlainText -Force;
                       Install-ADDSForest -ForestMode $ForestMode -DomainMode $DomainMode -DomainName $DomainName -InstallDns -SafeModeAdministratorPassword $DSRMPWord -Force'
Write-Verbose -Message "Deploying Virtual Machines with Names: [$DCVMName,$ADCVMName] using Template: [$SourceVMTemplate] and Customization Specification: [$SourceCustomSpec,$ASourceCustomSpec] on Cluster: [$TargetCluster] and waiting for completion" -Verbose
New-VM -Name $DCVMName -Template $SourceVMTemplate -ResourcePool $TargetCluster -OSCustomizationSpec $SourceCustomSpec -Datastore $Datastore -DiskStorageFormat Thin -RunAsync
New-VM -Name $ADCVMName -Template $SourceVMTemplate -ResourcePool $TargetCluster -OSCustomizationSpec $ASourceCustomSpec -Datastore $Datastore -DiskStorageFormat Thin -RunAsync
Start-Sleep -Seconds 5
	while($True)
	{
		$DCvmdeployEvents = Get-VIEvent -Entity $DCVMName 
		$DCdeployedEvent = $DCvmdeployEvents | Where-Object { $_.GetType().Name -eq "VmReconfiguredEvent" }
		if ($DCdeployedEvent)
		{
			break	
		}
		else 	
		{
			Start-Sleep -Seconds 5
		}
	}
Write-Verbose -Message "Virtual Machine $DCVMName Deployed. Powering On" -Verbose
Start-VM -VM $DCVMName | Out-Null
Write-Verbose -Message "Verifying that Customization for VM $DCVMName has started ... Please Wait .. " -Verbose
	while($True)
	{
		$DCvmEvents = Get-VIEvent -Entity $DCVMName 
		$DCstartedEvent = $DCvmEvents | Where-Object { $_.GetType().Name -eq "CustomizationStartedEvent" }
		if ($DCstartedEvent)
		{
			break	
		}
		else 	
		{
			Start-Sleep -Seconds 5
		}
	}
Write-Verbose -Message "Customization of VM $DCVMName has started. Checking for Completed Status......." -Verbose
	while($True)
	{
		$DCvmEvents = Get-VIEvent -Entity $DCVMName 
		$DCSucceededEvent = $DCvmEvents | Where-Object { $_.GetType().Name -eq "CustomizationSucceeded" }
        $DCFailureEvent = $DCvmEvents | Where-Object { $_.GetType().Name -eq "CustomizationFailed" }
 
		if ($DCFailureEvent)
		{
			Write-Warning -Message "Customization of VM $DCVMName failed" -Verbose
            return $False	
		}
		if ($DCSucceededEvent) 	
		{
            break
		}
        Start-Sleep -Seconds 5
	}
Write-Verbose -Message "Customization of VM $DCVMName Completed Successfully!" -Verbose
Start-Sleep -Seconds 30
Write-Verbose -Message "Virtual Machine $ADCVMName Deployed. Powering On" -Verbose
Start-VM -VM $ADCVMName | Out-Null
Write-Verbose -Message "Waiting for VM $DCVMName to complete post-customization reboot." -Verbose
Wait-Tools -VM $DCVMName -TimeoutSeconds 300 | Select-Object Powerstate,Guest
Start-Sleep -Seconds 30
Write-Verbose -Message "Getting ready to change IP Settings on VM $DCVMName." -Verbose
Invoke-VMScript -ScriptText $DCNetworkSettings -VM "$DCVMName" -GuestCredential $DCLocalCredential | Out-Null
Start-Sleep 30
$DCEffectiveAddress = (Get-VM $DCVMName).guest.ipaddress[0]
Write-Verbose -Message "Assigned IP for VM [$DCVMName] is [$DCEffectiveAddress]" -Verbose
Write-Verbose -Message "Getting Ready to Install Active Directory Services on $DCVMName" -Verbose
Invoke-VMScript -ScriptText $InstallADRole -VM $DCVMName -GuestCredential $DCLocalCredential | Out-Null
Write-Verbose -Message "Getting Ready to Install DNS Services on $DCVMName" -Verbose
Invoke-VMScript -ScriptText $InstallDNSRole -VM $DCVMName -GuestCredential $DCLocalCredential | Out-Null
Write-Verbose -Message "Configuring New AD Forest on $DCVMName" -Verbose
Invoke-VMScript -ScriptText $ConfigureNewDomain -VM $DCVMName -GuestCredential $DCLocalCredential -ErrorAction SilentlyContinue | Out-Null
Write-Verbose -Message "Rebooting $DCVMName to Complete Forest Provisioning" -Verbose
Start-Sleep -Seconds 120
Wait-Tools -VM $DCVMName -TimeoutSeconds 300 | Select-Object Powerstate,Guest
Start-Sleep -Seconds 120
Write-Verbose -Message "Validating that provisioning a new AD Forest succeeded on $DCVMName" -Verbose
$internalCheckDC = " `$attempt = 0
	while (`$attempt -lt 120 ) {
	`$event = Get-WinEvent -FilterHashtable @{LogName=`"Directory Service`"; Id=1000} -ErrorAction SilentlyContinue
	if (`$event) {
	Write-Host `"Event ID 1000 Found .. VM is a DC`"
	break
	} else {
	Start-Sleep -seconds 5 ; `$attempt++
	}
	} "
$CheckDC = Invoke-VMScript -ScriptText $internalCheckDC -VM $DCVMName -GuestCredential $DCLocalCredential
if ($CheckDC.ScriptOutput -eq "Event ID 1000 Found .. VM is a DC`r`n" ) {
Write-Host -fore green "`r`nVM $DCVMName is now a Domain Controller`r`n"
} else {
Write-Host -fore red "Script Failed .. Exiting" ; Exit }
Write-Verbose -Message "Installation of Domain Services and Forest Provisioning on $DCVMName Complete" -Verbose

#---------------------------------------------------STAGE 2-------------------------------------------------------------------------------

$DCLocalUser = "Administrator"
$DCLocalPWord = ConvertTo-SecureString -String "P@ssw0rd" -AsPlainText -Force
$DCLocalCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $DCLocalUser, $DCLocalPWord
$ADCNetworkSettings = 'netsh interface ip set address "Ethernet0" static 172.16.4.247 255.255.255.0 172.16.4.1'
$ADCDNSSettings = 'netsh interface ip set dnsservers name="Ethernet0" static 172.16.4.254 primary'
$InstallADRole = 'Install-WindowsFeature -Name "AD-Domain-Services" -IncludeManagementTools -Restart'
$JoinDomain = 	'$DomainName = "TestDomain.lcl";
				$DomainAdmin = "TestDomain\Administrator";
				$DomainAdminPass = ConvertTo-SecureString -String "P@ssw0rd" -AsPlainText -Force;
				$DomainCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $DomainAdmin, $DomainAdminPass;
				Add-Computer -DomainName $DomainName -Credential $DomainCredential'
$PromoteADC =   '$DSRMPWord = ConvertTo-SecureString -String "P@ssw0rd" -AsPlainText -Force;
				$DomainName = "TestDomain.lcl"
				Install-ADDSDomainController -DomainName $DomainName -NoGlobalCatalog:$true -InstallDNS:$false -SafeModeAdministratorPassword $DSRMPWord -Force'

$DomainAdmin = "TESTDOMAIN\Administrator"
$DomainAdminPWord = ConvertTo-SecureString -String "P@ssw0rd" -AsPlainText -Force
$DomainAdminCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $DomainAdmin, $DomainAdminPWord
Write-Verbose -Message "Verifying that Customization for VM $ADCVMName has started ..." -Verbose
	while($True)
	{
		$DCvmEvents = Get-VIEvent -Entity $ADCVMName
		$DCstartedEvent = $DCvmEvents | Where-Object { $_.GetType().Name -eq "CustomizationStartedEvent" }
		if ($DCstartedEvent)
		{
			break	
		}
		else 	
		{
			Start-Sleep -Seconds 5
		}
	}
Write-Verbose -Message "Customization of VM $ADCVMName has started. Checking for Completed Status......." -Verbose
	while($True)
	{
		$DCvmEvents = Get-VIEvent -Entity $ADCVMName 
		$DCSucceededEvent = $DCvmEvents | Where-Object { $_.GetType().Name -eq "CustomizationSucceeded" }
        $DCFailureEvent = $DCvmEvents | Where-Object { $_.GetType().Name -eq "CustomizationFailed" }
		if ($DCFailureEvent)
		{
			Write-Warning -Message "Customization of VM $ADCVMName failed" -Verbose
            return $False	
		}
		if ($DCSucceededEvent) 	
		{
            break
		}
        Start-Sleep -Seconds 5
	}
Write-Verbose -Message "Customization of VM $ADCVMName Completed Successfully!" -Verbose
Start-Sleep -Seconds 30
Write-Verbose -Message "Waiting for VM $ADCVMName to complete post-customization reboot." -Verbose
Wait-Tools -VM $ADCVMName -TimeoutSeconds 300 | Select-Object Powerstate,Guest
Start-Sleep -Seconds 30
Invoke-VMScript -ScriptText $ADCNetworkSettings -VM $ADCVMName -GuestCredential $DCLocalCredential | Out-Null
Start-Sleep -Seconds 30
Invoke-VMScript -ScriptText $ADCDNSSettings -VM $ADCVMName -GuestCredential $DCLocalCredential | Out-Null
$DCEffectiveAddress = (Get-VM $ADCVMName).guest.ipaddress[0]
Write-Verbose -Message "Assigned IP for VM [$ADCVMName] is [$DCEffectiveAddress]" -Verbose
Start-Sleep -Seconds 30
Write-Verbose -Message "Getting Ready to Install Additional Domain Controller on $ADCVMName" -Verbose
Invoke-VMScript -ScriptText $InstallADRole -VM $ADCVMName -GuestCredential $DCLocalCredential | Out-Null
Write-Verbose -Message "Joining AD and Rebooting on $ADCVMName" -Verbose
Invoke-VMScript -ScriptText $JoinDomain -VM $ADCVMName -GuestCredential $DCLocalCredential | Out-Null
Start-Sleep -Seconds 30
Write-Verbose -Message "Rebooting $ADCVMName to Complete Joining Domain" -Verbose
Wait-Tools -VM $ADCVMName -TimeoutSeconds 300 | Select-Object Powerstate,Guest
Start-Sleep -Seconds 30
Write-Verbose -Message "Promoting $ADCVMName to Complete the Infrastructure" -Verbose
Invoke-VMScript -ScriptText $PromoteADC -VM $ADCVMName -GuestCredential $DomainAdminCredential -ErrorAction SilentlyContinue | Out-Null
Start-Sleep -Seconds 30
Wait-Tools -VM $ADCVMName -TimeoutSeconds 300 | Select-Object Powerstate,Guest
Start-Sleep -Seconds 30
Invoke-VMScript -VM "$DCVMName" -GuestCredential $DomainAdminCredential -ScriptText 'Get-ADDomainController -Filter * | Select Hostname,IPv4Address,IsGlobalCatalog,OperationMasterRoles,OperatingSystem' | Select-Object ScriptOutput
Write-Verbose -Message "Installation of Domain Services and Forest Provisioning on $ADCVMName Complete" -Verbose

#---------------------------------------------------End of Script 2-------------------------------------------------------------------------------