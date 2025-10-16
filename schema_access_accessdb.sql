-- Access schema DDL generated from template database

CREATE TABLE [Files] (
    [ID] AUTOINCREMENT PRIMARY KEY,
    [FileName] TEXT(255) NULL,
    [FileLoc] TEXT(255) NULL,
    [ImportDate] DATETIME NULL,
    [reportName] TEXT(255) NULL
);

CREATE TABLE [HostEnumeratedPorts] (
    [ID] AUTOINCREMENT PRIMARY KEY,
    [HostID] LONG NULL,
    [Port] LONG NULL,
    [Protocol] TEXT(10) NULL,
    [State] TEXT(50) NULL
);

CREATE TABLE [Hosts] (
    [ID] AUTOINCREMENT PRIMARY KEY,
    [FileID] LONG NULL,
    [name] TEXT(255) NULL,
    [operating-system] TEXT(255) NULL,
    [ssh-auth-meth] TEXT(255) NULL,
    [mac-address] MEMO NULL,
    [ssh-login-used] TEXT(255) NULL,
    [local-checks-proto] TEXT(255) NULL,
    [HOST_START] TEXT(255) NULL,
    [HOST_END] TEXT(255) NULL,
    [host-fqdn] TEXT(255) NULL,
    [host-ip] TEXT(255) NULL,
    [netbios-name] TEXT(255) NULL,
    [system-type] TEXT(255) NULL,
    [smb-login-used] TEXT(255) NULL,
    CONSTRAINT [FK_Hosts_Files_FileID_1] FOREIGN KEY ([FileID]) REFERENCES [Files]([ID]) ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE [HostTags] (
    [ID] AUTOINCREMENT PRIMARY KEY,
    [HostID] LONG NULL,
    [TagName] TEXT(255) NULL,
    [TagValue] MEMO NULL
);

CREATE TABLE [PluginInfo] (
    [ID] AUTOINCREMENT PRIMARY KEY,
    [pluginID] LONG NULL,
    [pluginHash] TEXT(255) NULL,
    [pluginName] MEMO NULL,
    [pluginFamily] TEXT(255) NULL,
    [description] MEMO NULL,
    [solution] MEMO NULL,
    [risk_factor] TEXT(255) NULL,
    [plugin_publication_date] TEXT(255) NULL,
    [synopsis] MEMO NULL,
    [see_also] MEMO NULL,
    [plugin_version] TEXT(255) NULL,
    [cvss_vector] TEXT(255) NULL,
    [cvss_base_score] TEXT(255) NULL,
    [bid] TEXT(255) NULL,
    [cve] MEMO NULL,
    [xref] MEMO NULL,
    [vuln_publication_date] TEXT(255) NULL,
    [plugin_modification_date] MEMO NULL,
    [exploitability_ease] MEMO NULL,
    [exploit_framework_core] MEMO NULL,
    [exploit_available] MEMO NULL,
    [exploit_framework_metasploit] TEXT(255) NULL,
    [metasploit_name] MEMO NULL,
    [cvss_temporal_vector] MEMO NULL,
    [cvss_temporal_score] MEMO NULL,
    [patch_publication_date] MEMO NULL,
    [plugin_type] MEMO NULL,
    [cpe] MEMO NULL,
    [exploit_framework_canvas] MEMO NULL,
    [canvas_package] MEMO NULL,
    [cm:compliance-check-name] TEXT(255) NULL,
    [fname] TEXT(255) NULL,
    [plugin_name] TEXT(255) NULL,
    [iavb] TEXT(255) NULL,
    [msft] TEXT(255) NULL,
    [osvdb] TEXT(255) NULL,
    [stig_severity] TEXT(255) NULL,
    [iava] TEXT(255) NULL,
    [edb-id] TEXT(255) NULL,
    [secunia] TEXT(255) NULL,
    [cwe] TEXT(255) NULL,
    [cisco-bug-id] TEXT(255) NULL,
    [cisco-sa] TEXT(255) NULL
);

CREATE TABLE [ReportItem] (
    [ID] AUTOINCREMENT PRIMARY KEY,
    [PID] LONG NULL,
    [HostID] LONG NULL,
    [port] LONG NULL,
    [svc_name] TEXT(255) NULL,
    [protocol] TEXT(255) NULL,
    [severity] LONG NULL,
    [plugin_output] MEMO NULL,
    CONSTRAINT [FK_ReportItem_Hosts_HostID_1] FOREIGN KEY ([HostID]) REFERENCES [Hosts]([ID]) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT [FK_ReportItem_PluginInfo_PID_2] FOREIGN KEY ([PID]) REFERENCES [PluginInfo]([ID]) ON UPDATE CASCADE ON DELETE CASCADE
);


