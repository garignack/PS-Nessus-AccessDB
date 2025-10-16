-- SQLite schema generated for PS-Nessus-DB imports
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS Files (
    ID INTEGER PRIMARY KEY AUTOINCREMENT,
    FileName TEXT,
    FileLoc TEXT,
    ImportDate TEXT,
    reportName TEXT
);

CREATE TABLE IF NOT EXISTS Hosts (
    ID INTEGER PRIMARY KEY AUTOINCREMENT,
    FileID INTEGER REFERENCES Files(ID) ON UPDATE CASCADE ON DELETE CASCADE,
    "name" TEXT,
    "operating-system" TEXT,
    "ssh-auth-meth" TEXT,
    "mac-address" TEXT,
    "ssh-login-used" TEXT,
    "local-checks-proto" TEXT,
    HOST_START TEXT,
    HOST_END TEXT,
    "host-fqdn" TEXT,
    "host-ip" TEXT,
    "netbios-name" TEXT,
    "system-type" TEXT,
    "smb-login-used" TEXT
);

CREATE TABLE IF NOT EXISTS HostEnumeratedPorts (
    ID INTEGER PRIMARY KEY AUTOINCREMENT,
    HostID INTEGER REFERENCES Hosts(ID) ON UPDATE CASCADE ON DELETE CASCADE,
    Port INTEGER,
    Protocol TEXT,
    State TEXT
);

CREATE TABLE IF NOT EXISTS HostTags (
    ID INTEGER PRIMARY KEY AUTOINCREMENT,
    HostID INTEGER REFERENCES Hosts(ID) ON UPDATE CASCADE ON DELETE CASCADE,
    TagName TEXT,
    TagValue TEXT
);

CREATE TABLE IF NOT EXISTS PluginInfo (
    ID INTEGER PRIMARY KEY AUTOINCREMENT,
    pluginID INTEGER,
    pluginHash TEXT UNIQUE,
    pluginName TEXT,
    pluginFamily TEXT,
    description TEXT,
    solution TEXT,
    risk_factor TEXT,
    plugin_publication_date TEXT,
    synopsis TEXT,
    see_also TEXT,
    plugin_version TEXT,
    cvss_vector TEXT,
    cvss_base_score TEXT,
    bid TEXT,
    cve TEXT,
    xref TEXT,
    vuln_publication_date TEXT,
    plugin_modification_date TEXT,
    exploitability_ease TEXT,
    exploit_framework_core TEXT,
    exploit_available TEXT,
    exploit_framework_metasploit TEXT,
    metasploit_name TEXT,
    cvss_temporal_vector TEXT,
    cvss_temporal_score TEXT,
    patch_publication_date TEXT,
    plugin_type TEXT,
    cpe TEXT,
    exploit_framework_canvas TEXT,
    canvas_package TEXT,
    "cm:compliance-check-name" TEXT,
    fname TEXT,
    plugin_name TEXT,
    iavb TEXT,
    msft TEXT,
    osvdb TEXT,
    stig_severity TEXT,
    iava TEXT,
    "edb-id" TEXT,
    secunia TEXT,
    cwe TEXT,
    "cisco-bug-id" TEXT,
    "cisco-sa" TEXT
);

CREATE TABLE IF NOT EXISTS ReportItem (
    ID INTEGER PRIMARY KEY AUTOINCREMENT,
    PID INTEGER REFERENCES PluginInfo(ID) ON UPDATE CASCADE ON DELETE CASCADE,
    HostID INTEGER REFERENCES Hosts(ID) ON UPDATE CASCADE ON DELETE CASCADE,
    port INTEGER,
    svc_name TEXT,
    protocol TEXT,
    severity INTEGER,
    plugin_output TEXT,
    "cm:compliance-result" TEXT,
    "cm:compliance-actual-value" TEXT
);
