# PowerCLI-Scripts
My PowerCLI scripts for VMware automation.
A collection of VMware PowerCLI scripts for automated deployment, configuration, and management of enterprise virtual infrastructure and Active Directory environments.

🚀 Current Scripts
📍 Active Directory + Additional Domain Controller Deployment in parallel

Description: Automates the end-to-end installation and promotion of Primary Domain Controllers (DC) and Additional Domain Controllers (ADC) on Windows Server infrastructure.

Key Features:

Automated installation of AD DS roles and management tools.

Forest and domain creation with customizable naming.

Automated staging and promotion of Additional Domain Controllers (ADC).

🛠 Prerequisites & Requirements
PowerShell: Version 5.1 or PowerShell 7.x+
Windows Server Template with VMtools installed

Modules Required:

VMware.PowerCLI (for vSphere automation)

Permissions: Administrative access to target vCenter Server.

# Install VMware PowerCLI Module
Install-Module -Name VMware.PowerCLI
