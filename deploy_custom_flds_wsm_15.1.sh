#!/bin/bash

set -e  # Exit on error

# Input check
if [[ $# -ne 2 || -z "$2" || ! -d "$1" ]]; then
    echo "Usage: $0 [\$PIN_HOME] [input .war ( BrmWebServices.war.CN.15.1.0.0.0-38709835 )] [output system (STD|CN)]"
    exit 1
fi

pin_home=$1
input_war_filename=$2
output_ext=$3

CUSTOM_FLDS_WSM_PATH="$pin_home/include/customfieldswsm"

SOURCE="$CUSTOM_FLDS_WSM_PATH/InfranetPropertiesAdditions.properties"
TARGET="${pin_home}/deploy/web_services/temp/WEB-INF/classes/Infranet.properties"
PATTERN="infranet.custom.field."

declare -A CUSTOM_SERVICE_MAP=(
  ["BRMARServices"]="ar"
  ["BRMBillServices"]="bill"
  ["BRMContractServices"]="contract"
  ["BRMCollectionsServices"]="collection"
  ["BRMCustServices"]="cust"
  ["BRMDepositServices"]="deposit"
  ["BRMPymtServices"]="pymt"
  ["BRMSubscriptionServices"]="subscription"
  ["BRMUMSServices"]="ums"
  ["BRMCustomServices"]="custom"
)


echo ' '
echo ' '
sh gen_custom_ops_fields.sh $pin_home
echo ' '
echo ' '

echo ' '
echo  'Extracting the' ${PIN_HOME}'/deploy/web_services/'${input_war_filename}' file to a local temp dir.'
mkdir -p ${pin_home}/deploy/web_services/temp
rm -rf ${pin_home}/deploy/web_services/temp/*
cd ${pin_home}/deploy/web_services/temp/..
cp -v  ${PIN_HOME}/deploy/web_services/${input_war_filename} ${pin_home}/deploy/web_services/temp/BrmWebServices.war
cd ${pin_home}/deploy/web_services/temp
jar -xvf BrmWebServices.war
echo ' ...Done'

echo ' '
echo 'Copying CustomFields.jar to '${pin_home}/deploy/web_services/temp'/WEB-INF/lib/'
cp -v  $CUSTOM_FLDS_WSM_PATH/CustomFields.jar ${pin_home}/deploy/web_services/temp/WEB-INF/lib/CustomFields.jar
echo ' ...Done'


echo 'Generating XSDs for the following xmls:'
cd $pin_home/apps/brm_integrations/WSM
ls *.xml
unset CLASSPATH
for i in *.xml; do 
    echo -n 'Generating XSD for' $i '...'; 
    # pin_opspec_to_schema_v2 $i; 
    echo 'Done';
done
mkdir -p "${pin_home}/deploy/web_services/temp/../schemas/custom/"
cp -v  *.xsd ${pin_home}/deploy/web_services/temp/../schemas/custom/
echo ' ...Done Generating XSDs'


echo ' '
echo 'Copy all XSDs to' ${pin_home}/apps/brm_integrations/config/../schemas/custom
mkdir -p "${pin_home}/apps/brm_integrations/config/../schemas/custom"
rm -f "${pin_home}/apps/brm_integrations/config/../schemas/custom/*"
cp -v  $pin_home/apps/brm_integrations/WSM/*.xsd ${pin_home}/apps/brm_integrations/config/../schemas/custom
echo ' ...Done'


echo "Creating directory: ${pin_home}/apps/brm_integrations/config/wsdl_gen"
mkdir -p "${pin_home}/apps/brm_integrations/config/wsdl_gen"
cd "${pin_home}/apps/brm_integrations/config/wsdl_gen"
rm -rf *
mkdir -p "${pin_home}/apps/brm_integrations/config/wsdl_gen/soap11"
mkdir -p "${pin_home}/apps/brm_integrations/config/wsdl_gen/soap12"


echo "Creating directory: schemas/merged and merging OOTB and Custom xsds"
mkdir -p "${pin_home}/apps/brm_integrations/schemas/merged"
cp  $pin_home/apps/brm_integrations/schemas/*.xsd ${pin_home}/apps/brm_integrations/schemas/merged/
cp  $pin_home/deploy/web_services/temp/WEB-INF/wsdl/*.xsd ${pin_home}/apps/brm_integrations/schemas/merged/
cp $pin_home/apps/brm_integrations/WSM/*.xsd ${pin_home}/apps/brm_integrations/schemas/merged/


echo ' '
echo 'Generating WSDLs for SOAP v1.1'
cd "${pin_home}/apps/brm_integrations/config/wsdl_gen/soap11"
pin_wsdl_generator -c ../../pin_wsdl_generator.xml -s XML



echo 'Generating WSDLs for SOAP v1.2'
cd "${pin_home}/apps/brm_integrations/config"

cp pin_wsdl_generator.xml pin_wsdl_generator_v12.xml
soap11='<soap-namespace prefix="soap">http://schemas.xmlsoap.org/wsdl/soap/</soap-namespace>'
soap12_new='<soap-namespace prefix="soap12">http://schemas.xmlsoap.org/wsdl/soap12/</soap-namespace>'
soap11_new='<soap11-namespace prefix="soap">http://schemas.xmlsoap.org/wsdl/soap/</soap11-namespace>'

# Escape & and / for sed safety
safe_soap11=$(printf '%s' "$soap11" | sed 's/[&/\]/\\&/g')
safe_soap12_new=$(printf '%s' "$soap12_new" | sed 's/[&/\]/\\&/g')
safe_soap11_new=$(printf '%s' "$soap11_new" | sed 's/[&/\]/\\&/g')
sed -i -E "s#^([[:space:]]*)${safe_soap11}#\1${safe_soap12_new}\n\1${safe_soap11_new}#g" pin_wsdl_generator_v12.xml

cd "${pin_home}/apps/brm_integrations/config/wsdl_gen/soap12"
pin_wsdl_generator -c ../../pin_wsdl_generator_v12.xml -s XML
for f in BRM*_v2.wsdl; do 
    sed -i -e 's/_ptt"/12_ptt"/g' "$f"
    sed -i -e 's/_pt"/12_pt"/g' "$f"
    sed -i -e 's/Service_binding"/Service12_binding"/g' "$f"
    sed -i -e 's/Services_v2"/Services12_v2"/g' "$f"
    mv "$f" "${f/_v2.wsdl/12_v2.wsdl}" 
done

rm -f ../../pin_wsdl_generator_v12.xml

echo 'Creating folder structure under '${pin_home}/apps/brm_integrations/custom_services' with folders wsdl src classes and jar'
mkdir -p "${pin_home}/apps/brm_integrations/custom_services"
rm -rf "${pin_home}/apps/brm_integrations/custom_services/wsdl/"
rm -rf "${pin_home}/apps/brm_integrations/custom_services/src/"
rm -rf "${pin_home}/apps/brm_integrations/custom_services/classes/"
rm -rf "${pin_home}/apps/brm_integrations/custom_services/jar/"
mkdir -p "${pin_home}/apps/brm_integrations/custom_services/wsdl/"
mkdir -p "${pin_home}/apps/brm_integrations/custom_services/src/"
mkdir -p "${pin_home}/apps/brm_integrations/custom_services/classes/"
mkdir -p "${pin_home}/apps/brm_integrations/custom_services/jar/"
echo ' ...Done'

echo ' '
echo 'Copying all split custom service WSDLs to '${pin_home}/apps/brm_integrations/custom_services'/wsdl'
rm -rf "${pin_home}/apps/brm_integrations/custom_services/wsdl/*"
cp  $pin_home/deploy/web_services/temp/WEB-INF/wsdl/*.xsd "${pin_home}/apps/brm_integrations/custom_services/wsdl/"

echo "Copying all generated wsdls into "${pin_home}/apps/brm_integrations/custom_services/wsdl/" and  ${pin_home}/deploy/web_services/temp/WEB-INF/wsdl/"
for genName in "${!CUSTOM_SERVICE_MAP[@]}"; do
    depName="${CUSTOM_SERVICE_MAP[$genName]}"
    echo "  -> ${genName}"
    if [[ "$genName" == "BRMCustomServices" ]]; then
        cp -v  "${pin_home}/apps/brm_integrations/config/wsdl_gen/soap11/BRMCustomServices_v2.wsdl"   "${pin_home}/apps/brm_integrations/custom_services/wsdl/BRMCUSTOMServices_v2.wsdl"
        cp -v  "${pin_home}/apps/brm_integrations/config/wsdl_gen/soap12/BRMCustomServices12_v2.wsdl" "${pin_home}/apps/brm_integrations/custom_services/wsdl/BRMCUSTOMServices12_v2.wsdl"

        cp -v "${pin_home}/apps/brm_integrations/config/wsdl_gen/soap11/BRMCustomServices_v2.wsdl"   "${pin_home}/deploy/web_services/temp/WEB-INF/wsdl/BRMCUSTOMServices_v2.wsdl"
        cp -v "${pin_home}/apps/brm_integrations/config/wsdl_gen/soap12/BRMCustomServices12_v2.wsdl" "${pin_home}/deploy/web_services/temp/WEB-INF/wsdl/BRMCUSTOMServices12_v2.wsdl"
    else
        cp -v  "${pin_home}/apps/brm_integrations/config/wsdl_gen/soap11/${genName}_v2.wsdl"   "${pin_home}/apps/brm_integrations/custom_services/wsdl/"
        cp -v  "${pin_home}/apps/brm_integrations/config/wsdl_gen/soap12/${genName}12_v2.wsdl" "${pin_home}/apps/brm_integrations/custom_services/wsdl/"

        cp -v "${pin_home}/apps/brm_integrations/config/wsdl_gen/soap11/${genName}_v2.wsdl"   "${pin_home}/deploy/web_services/temp/WEB-INF/wsdl/"
        cp -v "${pin_home}/apps/brm_integrations/config/wsdl_gen/soap12/${genName}12_v2.wsdl" "${pin_home}/deploy/web_services/temp/WEB-INF/wsdl/"
    fi
done
echo ' ...Done'


echo ' '
echo 'Copying all xsd files from '$pin_home'/apps/brm_integrations/WSM to '${pin_home}/apps/brm_integrations/custom_services'/wsdl'
cp -v  $pin_home/apps/brm_integrations/WSM/*.xsd ${pin_home}/apps/brm_integrations/custom_services/wsdl
cp -v  $pin_home/apps/brm_integrations/WSM/*.xsd "${pin_home}/deploy/web_services/temp/WEB-INF/wsdl/"
echo ' ...Done'

echo ' '
echo 'Copying the BrmWebServices.war/WEB-INF/wsdl/BRMWebServiceException.xsd file into the local_dir/wsdl directory'
cp -v  ${pin_home}/deploy/web_services/temp/WEB-INF/wsdl/BRMWebServiceException.xsd ${pin_home}/apps/brm_integrations/custom_services/wsdl
echo ' ...Done'


echo ' '
echo 'Copying the following files to the local_dir/jar directory'
cp -v  ${pin_home}/deploy/web_services/temp/WEB-INF/lib/web_services.jar ${pin_home}/apps/brm_integrations/custom_services/jar
cp -v  ${pin_home}/deploy/web_services/temp/WEB-INF/lib/webserviceUtils.jar ${pin_home}/apps/brm_integrations/custom_services/jar
echo ' ...Done'

echo ' '
echo 'Copying the '${pin_home}/apps/brm_integrations/custom_services'/../httpsfilter/*.java to '${pin_home}/apps/brm_integrations/custom_services'/src/com/portal/jax/custom/filter directory'
mkdir -p ${pin_home}/apps/brm_integrations/custom_services/src/com/portal/jax/custom/filter
cp -v  ${pin_home}/apps/brm_integrations/custom_services/../httpsfilter/*.java ${pin_home}/apps/brm_integrations/custom_services/src/com/portal/jax/custom/filter/
echo ' ...Done'

cp /app/Middleware/Oracle_Home/oracle_common/modules/javax.servlet.javax.servlet-api.jar \
   /app/pin/BRM/apps/brm_integrations/custom_services/jar/


echo ' '
echo 'Compiling '${pin_home}/apps/brm_integrations/custom_services'/custom_services.jar'
cd ${pin_home}/apps/brm_integrations/custom_services
/app/Middleware/Oracle_Home/oracle_common/modules/thirdparty/org.apache.ant/1.10.5.0.0/apache-ant-1.10.5/bin/ant -file custom_services.xml
echo ' ...Done Compiling'

echo ' '
echo 'Copying custom_services.jar into the '${pin_home}/deploy/web_services/temp'/WEB-INF/lib directory'
cp -v  ${pin_home}/apps/brm_integrations/custom_services/custom_services.jar ${pin_home}/deploy/web_services/temp/WEB-INF/lib/
echo ' ...Done'

# merging all changes to the classes directory
for genName in "${!CUSTOM_SERVICE_MAP[@]}"; do
    dirName="${CUSTOM_SERVICE_MAP[$genName]}"
    cp -rf ${pin_home}/apps/brm_integrations/custom_services/classes/com/portal/jax/${dirName} ${pin_home}/deploy/web_services/temp/WEB-INF/classes/com/portal/jax/
done
cd ${pin_home}/deploy/web_services/temp/WEB-INF/classes
jar -cf ${pin_home}/deploy/web_services/temp/WEB-INF/lib/web_services.jar .


# Path to WSDLs and HTML file
WSDL_DIR="/app/pin/BRM/deploy/web_services/temp/WEB-INF/wsdl"
HTML_FILE="${pin_home}/deploy/web_services/temp/../index.html"



echo ' '
echo ' '
echo ' '
echo 'Updating index.html with all the updated WSDL links created/added'
# Build the SOAP 1.2 list
soap12_list=""
while IFS= read -r wsdl; do
   service="${wsdl%.wsdl}"
   soap12_list+="        <li><a href=\"${service}?WSDL\">${service}</a><br/>\n"
done < <(ls -1 "$WSDL_DIR"/*12_v2.wsdl 2>/dev/null | sort | xargs -n1 basename)

# Build the SOAP 1.1 list (exclude *12_v2.wsdl)
soap11_list=""
while IFS= read -r wsdl; do
   service="${wsdl%.wsdl}"
   soap11_list+="        <li><a href=\"${service}?WSDL\">${service}</a><br/>\n"
done < <(ls -1 "$WSDL_DIR"/*_v2.wsdl 2>/dev/null | grep -v '12_v2.wsdl$' | sort | xargs -n1 basename)

# Update HTML for SOAP 1.2
tmpfile=$(mktemp)
awk -v newlist="$soap12_list" '
   /<h2> Available SOAP 1.2 Services<\/h2>/ {
       print
       getline
       print newlist
       while (getline && $0 !~ /<\/ul>/) {}
       print "</ul>"
       next
   }
   { print }
' "$HTML_FILE" > "$tmpfile" && mv "$tmpfile" "$HTML_FILE"

# Update HTML for SOAP 1.1
tmpfile=$(mktemp)
awk -v newlist="$soap11_list" '
   /<h2> Available SOAP 1.1 Services<\/h2>/ {
       print
       getline
       print newlist
       while (getline && $0 !~ /<\/ul>/) {}
       print "</ul>"
       next
   }
   { print }
' "$HTML_FILE" > "$tmpfile" && mv "$tmpfile" "$HTML_FILE" 


cd ${pin_home}/deploy/web_services/temp/WEB-INF/
awk -f ${pin_home}/deploy/web_services/temp/../custom_sun_jaws.awk sun-jaxws.xml > tmp && mv tmp sun-jaxws.xml

cd ${pin_home}/deploy/web_services/temp/WEB-INF/
awk -f ${pin_home}/deploy/web_services/temp/../custom_web_xml.awk web.xml > tmp && mv tmp web.xml


cd ${pin_home}/deploy/web_services/temp
echo 'Removing the existing BrmWebServices.war file from '${pin_home}/deploy/web_services/temp' directory '
rm -f ${pin_home}/deploy/web_services/temp/BrmWebServices.war
echo ' ...Done'

echo ' '
echo 'Copying index.html into the '${pin_home}/deploy/web_services/temp'/index.html directory'
cp ${pin_home}/deploy/web_services/temp/../index.html ${pin_home}/deploy/web_services/temp/index.html
echo ' ...Done'


if [[ -z "$3" ]]; then
    build_type="BOTH"
else
    build_type="$3"
fi

if [[ "$build_type" = "STD" || "$build_type" = "BOTH" ]]; then
    ########## PREPARING STD INFRANET PROPS AND BUILDING WAR #####################
    echo ' '
    echo 'Updating Infranet Properties STD'
    cp -v  $CUSTOM_FLDS_WSM_PATH/InfranetPropertiesAdditions.properties ${pin_home}/deploy/web_services/temp/../InfranetPropertiesAdditions.properties
    cp -v  ${pin_home}/deploy/web_services/temp/../Infranet.properties.STD $TARGET
    cat ${pin_home}/deploy/web_services/temp/../InfranetPropertiesAdditions.properties >> $TARGET
    echo ' ...Done'

    echo 'Creating new BrmWebServices.war file to '${pin_home}/deploy/web_services/temp/..' directory '
    jar -cf BrmWebServices.war *
    mv BrmWebServices.war ../BrmWebServices.STD.war
    echo ' ...Done'
fi


if [[ "$build_type" = "CN" || "$build_type" = "BOTH" ]]; then
    ########## PREPARING CN INFRANET PROPS AND BUILDING WAR #####################
    echo 'Updating Infranet Properties CN'
    cp -v  $CUSTOM_FLDS_WSM_PATH/InfranetPropertiesAdditions.properties ${pin_home}/deploy/web_services/temp/../InfranetPropertiesAdditions.properties
    cp -v  ${pin_home}/deploy/web_services/temp/../Infranet.properties.CN $TARGET
    cat ${pin_home}/deploy/web_services/temp/../InfranetPropertiesAdditions.properties >> $TARGET
    echo ' ...Done'

    echo 'Creating new BrmWebServices.war file to '${pin_home}/deploy/web_services/temp/..' directory '
    jar -cf BrmWebServices.war *
    mv BrmWebServices.war ../BrmWebServices.CN.war
    echo ' ...Done'
fi

cd $pin_home/include
