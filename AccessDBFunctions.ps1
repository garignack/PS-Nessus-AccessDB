function run-AccessNoQuery {
    param ( 
     [string]$sql, 
     [System.Data.OleDb.OleDbConnection]$connection 
    ) 
        $cmd = New-Object System.Data.OleDb.OleDbCommand($sql, $connection) 
        $cmd.ExecuteNonQuery() 
}


function Get-AccessData { 
param ( 
    [string]$sql, 
    [System.Data.OleDb.OleDbConnection]$connection, 
    [switch]$grid 
) 
    
    $cmd = New-Object System.Data.OleDb.OleDbCommand($sql, $connection) 
    $reader = $cmd.ExecuteReader() 
    
    $dt = New-Object System.Data.DataTable 
    $dt.Load($reader) 
    
    if ($grid) {$dt | Out-GridView -Title "$sql" } 
    else {$dt} 

}  

function add-AccessData([String]$table, [Array]$Param, [Array]$Values, [System.Data.OleDb.OleDbConnection]$connection){
    $return = "INSERT INTO $table ("
    for ($j=0; $j -lt $Param.count; $j++){
        $return += "[$($Param[$j])]"
        if ( $j -lt ($Param.count-1) ){
            $return += ', '
        }
    } 
    $return += ") VALUES ("
    for ($j=0; $j -lt $Values.count; $j++){
        $return += "'"
        $return += $Values[$j]
        $return += "'"
        if ( $j -lt ($Values.count-1)){
            $return += ', '
        }
    } 
    $return += ")"
        
    $cmd = New-Object System.Data.OleDb.OleDbCommand($return, $connection) 
    $iAffected = $cmd.ExecuteNonQuery()
    
    $cmd2 = New-Object System.Data.OleDb.OleDbCommand("SELECT @@IDENTITY;", $connection)
    [int]$recordID = $cmd2.ExecuteScalar()
    
    $recordID
}

function fix-SQLColumns([String]$table, [Array]$Columns, [System.Data.OleDb.OleDbConnection]$connection){
    
    $connColumns = $connection.GetSchema("columns") | where-object{$_.TABLE_NAME -eq $table} | foreach{$_.COLUMN_NAME}
    
    for ($j=0; $j -lt $Columns.count; $j++){
        if (($connColumns -contains $columns[$j]) -ne $true){
            $sqlAlter = "ALTER TABLE $table ADD COLUMN [$($columns[$j])] TEXT(255)"
            $cmdAdd = New-Object System.Data.OleDb.OleDbCommand($sqlAlter, $conn)
            $cmdAdd.ExecuteNonQuery()
        } 
    }
    
}

function get-SQLEscaping ([string]$sql){
 
# [ --> [[]
    $sql = $sql.replace("`[", '`[`[`]')
# ' --> ''
    $sql = $sql.replace("`'", "`'`'")
# " --> ""
    $sql = $sql.replace('`"', '`"`"')
# ? --> [?]
    $sql = $sql.replace('?', '`[?`]')
# * -->[*]
    $sql = $sql.replace('*', '`[*`]')
# # --> [#]
    $sql = $sql.replace('#', '`[#`]')
# New line characters 
    $sql = $sql.replace("`n", "\n")
	$sql = $sql.replace("`r", "\r")
    $sql
}

function add-CSVtoTable([String]$table, [String]$fileLoc, [System.Data.OleDb.OleDbConnection]$connection){
    
}

function update_or_create_by_id ([String]$table, [string]$ID, [Array]$Param, [Array]$Values,[System.Data.OleDb.OleDbConnection]$connection){
    $result = Get-AccessData "SELECT ID  from $table where ID = $id" $conn
    if ($result) {
    $sql = "UPDATE $table SET "
    for ($j=0; $j -lt $Param.count; $j++){
        $sql += "[$($Param[$j])] = '$($Values[$j])'"
        if ( $j -lt ($Param.count-1) ){
            $sql += ', '
        }
    } 
    $sql += "WHERE ID = $id;"
    $cmd = New-Object System.Data.OleDb.OleDbCommand($sql, $connection) 
    $cmd.ExecuteNonQuery()
    $id
    } else {
    
    add-AccessData $table $Param $Values $conn
    
    }
}


