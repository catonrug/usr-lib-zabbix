
##############################################################
# Zabbix SNMP template DEV scenario
# scan which OID contains value mapping. create only them
# create items directly into interface by passing hostid
##############################################################

WORKDIR=/usr/lib/zabbix/snmp
MIB=SOCOMECUPS-MIB-6-20
ENTERPRISES=1.3.6.1.4.1.4555
API_JSONRPC=https://zabbix.aigarskadikis.com/api_jsonrpc.php
SID=64659f1aa207b62a1bac86a4385435ba
IP=10.100.0.16
PORT=161
# GET INTERFACE ID
curl --silent --insecure --request POST --header 'Content-Type: application/json-rpc' --data '{"jsonrpc": "2.0","method": "hostinterface.get","params": {"output": ["interfaceid"],"hostids": "13555","filter": {"main": "1","port": "161"}},"auth": "64659f1aaf07b61a1bac86a4385435ba","id": 1}' https://zabbix.aigarskadikis.com/api_jsonrpc.php | jq -r .result[0].interfaceid

# get 'snmpwalk' command working
snmpwalk -c'public' -v'2c' $IP:$PORT .

# make sure standart MIBS are installed in the system
cd /usr/share/snmp/mibs && ls -1

# create directory 'dev' to start developent
mkdir -p $WORKDIR

# create 1 file there which is a very standalone file and does not interfer with system (to avoid MIB conflicts)
ls -lh $WORKDIR/$MIB

# the original MIB name usually hides behind
grep 'DEFINITIONS ::= BEGIN' $WORKDIR/$MIB
grep 'DEFINITIONS ::= BEGIN' $WORKDIR/$MIB | grep -Eo "^\S+"

# Use 'snmptranslate' to list all available metrics
snmptranslate -Tz -m ./$MIB

# based on previous keyword, print all OIDs
snmptranslate -Tz -m ./$MIB | grep Status | grep -Eo "1\.3\.6\.[0-9.]+"

# start a bash loop and scan each individual OID, to make sure this particula device is having this OID
# if OID has found then snmptranslate the meaning AND look for anything with a value map
# in no value map, then nothing happens. if value map is there then print OID
# type 20 = SNMP agent
# value_type = integer
echo "1.3.6.1.4.1.4555.1.1.1.1.4.1"

cd $WORKDIR && snmptranslate -Tz -m ./$MIB | grep -E "$ENTERPRISES.[0-9.]+"

cd $WORKDIR && snmptranslate -Tz -m ./$MIB | grep Status | grep -Eo "$ENTERPRISES.[0-9.]+" | while IFS= read -r OID
do {
snmpwalk -c'public' -v'2c' $IP:$PORT .$OID > /dev/null && \
snmptranslate -m ./$MIB -Td .$OID | grep SYNTAX.*INTEGER.*{.*} > /dev/null && \
snmpwalk -On -c'public' -v'2c' $IP:$PORT .$OID.0 && \
echo .$OID.0 && \
VALUE_MAP_NAME=$(snmptranslate -m ./$MIB .$OID) && \
OIDNAME=$(snmptranslate -m ./$MIB .$OID | grep -Eo "[a-zA-Z0-9]+$") && \
echo $OIDNAME && \
OIDDESCRIPTION=$(snmptranslate -m ./$MIB .$OID -Td | tr -d '\n' | sed 's|^.*DESCRIPTION\s*||' | sed -e's/  */ /g' | sed 's|^\d034||' | sed 's|\d034.*$||') && \
snmptranslate -m ./$MIB -Td .$OID | grep SYNTAX.*INTEGER.*{.*} | sed 's|^.*{||;s|}||;s|, |\n|g' && \
VALUE_MAP=$(snmptranslate -m ./$MIB -Td .$OID | grep SYNTAX.*INTEGER.*{.*} | sed 's|^.*{||;s|}||;s|, |\n|g' | sed 's/^[ \t]*//' | sed 's|^|{"newvalue":"|' | sed 's|(|","value":"|' | sed 's|)|"},|' | tr -d '\n' | sed 's|,\s*$||' | sed 's|\d034|\\\d034|g') && \
echo $VALUE_MAP && \
VALUE_MAP_ID=$(zabbix_js -s create.value.map.js -p "
      {\"name\":\"$VALUE_MAP_NAME\",
   \"mappings\":\"$VALUE_MAP\",
\"api_jsonrpc\":\"$API_JSONRPC\",
        \"sid\":\"$SID\"}
" | grep -Eo "[0-9]+") && \
curl --silent --insecure --request POST --header 'Content-Type: application/json-rpc' --data "
{
\"jsonrpc\": \"2.0\",
\"method\": \"item.create\",
\"params\": {
\"name\": \"$OIDNAME\",
\"key_\": \".$OID.0\",
\"description\": \"$OIDDESCRIPTION\",
\"snmp_oid\": \"$OID.0\",
\"hostid\": \"13555\",
\"type\": 20,
\"value_type\": 3,
\"interfaceid\": \"2299\",
\"valuemapid\":\"$VALUE_MAP_ID\",
\"delay\": \"30s\"
},
\"auth\": \"$SID\",
\"id\": 1
}
" $API_JSONRPC | jq . && \
echo "VALUE_MAP_ID is $VALUE_MAP_ID"
} done
zabbix_server -R config_cache_reload


