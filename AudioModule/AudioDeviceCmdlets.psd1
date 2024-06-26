#
# Copyright (c) 2016-2022 Francois Gendron <fg@frgn.ca>
# MIT License
#
# AudioDeviceCmdlets.psd1
# Module manifest for module 'AudioDeviceCmdlets'
#

@{

# Script module or binary module file associated with this manifest
RootModule = 'AudioDeviceCmdlets.dll'

# Version number of this module.
ModuleVersion = '3.1.0.2'

# ID used to uniquely identify this module
GUID = '7156b1c0-8e86-4d19-8df1-058c15629f36'

# Author of this module
Author = 'Francois Gendron <fg@frgn.ca>'

# Company or vendor of this module
CompanyName = 'frgnca'

# Copyright statement for this module
Copyright = '(c) 2016-2022 Francois Gendron <fg@frgn.ca>'

# Description of the functionality provided by this module
Description = 'AudioDeviceCmdlets is a suite of PowerShell Cmdlets to control audio devices on Windows'

# Minimum version of the Windows PowerShell engine required by this module
PowerShellVersion = '3.0'

# Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
FunctionsToExport = @()

# Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
CmdletsToExport = 'Get-AudioDevice', 'Set-AudioDevice', 'Write-AudioDevice'

# Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.
AliasesToExport = @()

# List of all files packaged with this module
FileList = 'AudioDeviceCmdlets.dll'

# Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
PrivateData = @{

    PSData = @{

        # Tags applied to this module. These help with module discovery in online galleries.
        Tags = 'audio','default','playback','recording','communication','device','session','volume','mute','mixer','toggle','switch','get','set'

        # A URL to the license for this module.
        LicenseUri = 'https://github.com/frgnca/AudioDeviceCmdlets/blob/master/LICENSE'

        # A URL to the main website for this project.
        ProjectUri = 'https://github.com/frgnca/AudioDeviceCmdlets'

        # ReleaseNotes of this module
        ReleaseNotes = 'Default communication devices can now be controlled separately from default devices'

    } # End of PSData hashtable
    
 } # End of PrivateData hashtable

# HelpInfo URI of this module
HelpInfoURI = 'https://github.com/frgnca/AudioDeviceCmdlets/blob/master/README.md'

}