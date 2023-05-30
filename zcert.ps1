$Folder = "$($home)\zscaler-cert-app-store"
$LogFile = "zcertlogs.txt"
$Store = Join-Path -Path $Folder -ChildPath "zscalerCAbundle.pem"
$appsenv = @{ openssl = "SSL_CERT_FILE"; 
                curl = "CURL_CA_BUNDLE"; 
                python = "REQUESTS_CA_BUNDLE";
                nodejs = "NODE_EXTRA_CA_CERTS";
                git = "GIT_SSL_CAPATH";
                aws = "AWS_CA_BUNDLE"
            }

function Add-Folder {
    ### Create Folder in user home ###
    try {
        if( -Not (Test-Path -Path $Folder ) )
        {
            New-Item -ItemType directory -Path $Folder
            $FILE = Get-Item $Folder -Force
            $FILE.attributes = 'Hidden'
            Write-Output "Folder created  zscaler-cert-app-store on user's home profile"
        }else{
            Write-Output "Folder already created. Skipping"
        }
    }
    catch {
        Write-Output "Can't create folder"
        Write-Output $_
    }
    ### Create Folder in user home ###
    try {
        $flocation = Join-Path -Path $Folder -ChildPath $LogFile
        if( -Not (Test-Path -Path $flocation -PathType Leaf) ){
            New-Item -ItemType File -Path $Folder -Name $LogFile
            Write-Output "Log file created in " + $flocation
        }else{
            Write-Output "Log file already created. Skipping"
        }
    }
    catch {
        Write-Output "Can't create log file"
        Write-Output $_
    }

}

function Test-Privileges {
    if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
        Write-Log 'Insufficient permissions to run this script. Open the PowerShell console as an administrator and run this script again.'
        Break
    }
}

Function Write-Log {
    Param ([string]$logstring)
    $LogLoc = Join-Path -Path $Folder -ChildPath $LogFile
    $Stamp = (Get-Date).toString("yyyy/MM/dd HH:mm:ss")
    $Line = "$Stamp $logstring"
    Write-Host $Line
    Add-content $LogLoc -value $Line
}

function New-Bundle{
    #if bundle exist alert it'll overwrite it
    if( Test-Path -Path $Store -PathType Leaf) {
        Write-Log "Certificate bundle detected. Clearing it..."
        Clear-Content $Store
    }
    Write-Log "Generating certificate bundle..."
    #getting all certs
    $certs=Get-ChildItem Cert: -Recurse  | Select-Object * 
    #making sure 
    $found = $false
    foreach($cert in $certs){
        if ($cert.Thumbprint -eq "D72F47D87420E3F0F9BDCAC6F03A566743C481B9"){
            $found = $true
        }
    }
    if ($found){
        Write-Log 'Zscaler root found.'
        #getting certificate authroities only
        foreach($cert in $certs){
            #going over extensiosn
            $ext =  $cert.Extensions
            $ca = $false
            foreach($e in $ext) {
                if ($e.CertificateAuthority -eq $true){
                    $ca = $true
                }
            }
            if ($ca){
                $line = [System.Convert]::ToBase64String($cert.RawData)
                $issuer = "# Issuer: "+$cert.IssuerName.Name+"`n"
                $subject = "# Subject: "+$cert.SubjectName.Name+"`n"
                $serial = "# Serial: "+$cert.SerialNumber+"`n"
                $thumbprint = "# Thumbprint: "+$cert.Thumbprint+"`n"
                Add-Content -NoNewline -Path $Store -Value $issuer
                Add-Content -NoNewline -Path $Store -Value $subject
                Add-Content -NoNewline -Path $Store -Value $serial
                Add-Content -NoNewline -Path $Store -Value $thumbprint
                Add-Content -NoNewline -Path $Store -Value "-----BEGIN CERTIFICATE-----`n"
                #pem is base 64 with new linex unix format every 64 characters
                
                for ($i = 0; $i -lt $line.Length; $i += 64)
                {
                    $length = [Math]::Min(64, $line.Length - $i)
                    $tmp = $line.SubString($i, $length)+ "`n"
                    Add-Content -NoNewline -Path $Store -Value $tmp
                }
                Add-Content -NoNewline -Path $Store -Value "-----END CERTIFICATE-----`n`n"
            }
        }
    }else{
        Write-Log 'Zscaler root certificate not found on system trusted root CA store. Please make sure ZCC is installed'
        Break
    }
    #identify thumbprint "D72F47D87420E3F0F9BDCAC6F03A566743C481B9"
}

function Update-Apps{
    foreach ($key in $appsenv.Keys) {
        # checking if key exist
        try{
            $tmp = $appsenv[$key]
            $env = Get-Childitem Env:$tmp -ErrorAction Stop
            Write-Log "Enviroment variable: $($appsenv[$key]) for $($key) already set to: $($env.Value) overwriting"
        }catch{ #not found
            Write-Log "Fixing: $($key)"
        }
        setx $appsenv[$key] "${Store}"
        Write-Log "Enviroment variable: $($appsenv[$key]) set to $($Store)"
    }
}



function Main {
    # Make sure it's being run as admin
    Test-Privileges
    # Adds new folder and log file
    Add-Folder
    #adds/rewrites certificate bundle
    New-Bundle
    #Adds enviroment variables for all programs
    Update-Apps
}

# Run Program
Main