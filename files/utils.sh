#!/bin/bash
set -e

export JBOSS_CLI=$JBOSS_HOME'/bin/jboss-cli.sh '
export WILDFLY_PID=0

: ${DEPLOYMENT_SCANNER:='true'}

function wait_for_server() {
  until `$JBOSS_CLI -c "ls /deployment" &> /dev/null`; do
    sleep 1
  done
}

function set_management_user() {
  : ${MANAGEMENT_USERNAME:='admin'}
  : ${MANAGEMENT_PASSWORD:='admin'}

  echo '=> Setting management user'
  $JBOSS_HOME/bin/add-user.sh $MANAGEMENT_USERNAME $MANAGEMENT_PASSWORD
}

function toggle_deployments_scanner() {
  $JBOSS_CLI --connect --user=$MANAGEMENT_USERNAME --password=$MANAGEMENT_PASSWORD --command='/subsystem=deployment-scanner/scanner=default:write-attribute(name="scan-enabled",value='${DEPLOYMENT_SCANNER}')'

  if [ "${DEPLOYMENT_SCANNER}" == "false" ] ; then DEPLOYMENT_SCANNER='true'; else DEPLOYMENT_SCANNER='false'; fi
}

function start_application_server_admin_only() {
  echo '=> Starting Wildfly - Admin Only Mode'
  $JBOSS_HOME/bin/standalone.sh -b 0.0.0.0 --admin-only &
  WILDFLY_PID=$!
}

function start_application_server() {
  echo '=> Starting Wildfly'
  $JBOSS_HOME/bin/standalone.sh -b 0.0.0.0 &
  WILDFLY_PID=$!
}

function kill_application_server() {
  kill -9 $WILDFLY_PID
}

function reload_application_server() {
  echo '=> Reloading Wildfly'
  $JBOSS_CLI --connect --user=$MANAGEMENT_USERNAME --password=$MANAGEMENT_PASSWORD --command=':shutdown(restart=true)'
}

function install_driver() {
  DS_DRIVER=$1
  install_${DS_DRIVER}_driver
}

function install_postgresql_driver() {
  echo '=> Installing PostgreSQL Driver'

  curl http://central.maven.org/maven2/org/postgresql/postgresql/42.2.5/postgresql-42.2.5.jar > postgresql.jar

  $JBOSS_CLI --connect --user=$MANAGEMENT_USERNAME --password=$MANAGEMENT_PASSWORD --command='module add --name=org.postgresql --resources=postgresql.jar 
--dependencies=javax.api,javax.transaction.api'

  $JBOSS_CLI --connect --user=$MANAGEMENT_USERNAME --password=$MANAGEMENT_PASSWORD --command='/subsystem=datasources/jdbc-driver=postgresql:add(driver-name=postgresql,driver-module-name=org.postgresql,driver-class-name=org.postgresql.Driver, driver-xa-datasource-class-name=org.postgresql.xa.PGXADataSource)'

  rm postgresql.jar
}

function install_oracle_driver() {
  echo '=> Installing Oracle Driver'
  curl http://repo.spring.io/plugins-release/com/oracle/ojdbc6/11.2.0.3/ojdbc6-11.2.0.3.jar > ojdbc6.jar

  $JBOSS_CLI --connect --user=$MANAGEMENT_USERNAME --password=$MANAGEMENT_PASSWORD --command='module add --name=com.oracle --resources=ojdbc6.jar 
--dependencies=javax.api,javax.transaction.api'

  $JBOSS_CLI --connect --user=$MANAGEMENT_USERNAME --password=$MANAGEMENT_PASSWORD --command='/subsystem=datasources/jdbc-driver=oracle:add(driver-name=oracle,driver-module-name=com.oracle,driver-class-name=oracle.jdbc.driver.OracleDriver,driver-xa-datasource-class-name=oracle.jdbc.xa.client.OracleXADataSource)'

}

function disable_welcome_page() {
  $JBOSS_CLI --connect --user=$MANAGEMENT_USERNAME --password=$MANAGEMENT_PASSWORD --command='/subsystem=undertow/server=default-server/host=default-host:remove'
}

function recover_datasource_from_secrets() {
  SECRET_NAME=$1

  if [ -f "/run/secrets/${SECRET_NAME}" ]; then
    DS_NAME=`grep -Po "DS_NAME=(.*)$" /run/secrets/${SECRET_NAME} | cut -d= -f2`
    DS_CONNECTION_URL=`grep -Po "DS_CONNECTION_URL=(.*)$" /run/secrets/${SECRET_NAME} | cut -d= -f2`
    DS_USERNAME=`grep -Po "DS_USERNAME=(.*)$" /run/secrets/${SECRET_NAME} | cut -d= -f2`
    DS_PASSWORD=`grep -Po "DS_PASSWORD=(.*)$" /run/secrets/${SECRET_NAME} | cut -d= -f2`
  else
    echo "O arquivo de secrets /run/secrets/${SECRET_NAME} não existe"
    exit 0
  fi
}

function enable_property_replacement() {
  $JBOSS_CLI --connect --user=$MANAGEMENT_USERNAME --password=$MANAGEMENT_PASSWORD --command='/subsystem=ee:write-attribute(name="spec-descriptor-property-replacement", value=true)'
}

function add_property() {
  PROPERTY_NAME=$1
  PROPERTY_VALUE=$2

  $JBOSS_CLI --connect --user=$MANAGEMENT_USERNAME --password=$MANAGEMENT_PASSWORD --command='/system-property='${PROPERTY_NAME}':add(value="'${PROPERTY_VALUE}'")'
}

function configure_datasource(){

  echo '=> Adding datasourse '$DS_NAME
  $JBOSS_CLI --connect --user=$MANAGEMENT_USERNAME --password=$MANAGEMENT_PASSWORD --command='/subsystem=datasources/data-source='$DS_NAME':add(
    jndi-name=java:/'$DS_NAME',
    driver-name='$DS_DRIVER',
    connection-url="'$DS_CONNECTION_URL'",
    user-name="'$DS_USERNAME'",
    password="'$DS_PASSWORD'",
    min-pool-size=5,
    max-pool-size=20,
    initial-pool-size=5,
    idle-timeout-minutes=3
  )'

  echo '=> Testing datasourse '$DS_NAME
  $JBOSS_CLI --connect --user=$MANAGEMENT_USERNAME --password=$MANAGEMENT_PASSWORD --command='/subsystem=datasources/data-source='$DS_NAME':test-connection-in-pool'
}

function configure_xa_datasource(){
  CONNECTION_CHECKER_CLASS=$1
  EXCEPTION_SORTER_CLASS=$2
  STALE_CONNECTION_CLASS=$3

  echo '=> Adding XA datasourse '$DS_NAME

  $JBOSS_CLI --connect --user=$MANAGEMENT_USERNAME --password=$MANAGEMENT_PASSWORD --command='/subsystem=datasources/xa-data-source='$DS_NAME':add(
    jndi-name=java:/'$DS_NAME',
    driver-name='$DS_DRIVER',
    user-name="'$DS_USERNAME'",
    password="'$DS_PASSWORD'",
    use-java-context=true,
    valid-connection-checker-class-name='$CONNECTION_CHECKER_CLASS',
    exception-sorter-class-name='$EXCEPTION_SORTER_CLASS',
    stale-connection-checker-class-name ='$STALE_CONNECTION_CLASS',
    check-valid-connection-sql="SELECT 1",
    idle-timeout-minutes=3,
    use-ccm=true,
    pool-prefill=true,
    enabled=false,
    validate-on-match=true,
    use-fast-fail=true
  )'

  $JBOSS_CLI --connect --user=$MANAGEMENT_USERNAME --password=$MANAGEMENT_PASSWORD --command='/subsystem=datasources/xa-data-source='$DS_NAME'/xa-datasource-properties=URL:add(value='$DS_CONNECTION_URL')';

  $JBOSS_CLI --connect --user=$MANAGEMENT_USERNAME --password=$MANAGEMENT_PASSWORD --command='xa-data-source enable --name='$DS_NAME 
}

function update_max_post_size() {
  echo '=> Increasing max-post-size to '$1
  $JBOSS_CLI --connect --user=$MANAGEMENT_USERNAME --password=$MANAGEMENT_PASSWORD --command='
/subsystem=undertow/server=default-server/http-listener=default/:write-attribute(name=max-post-size,value='$1')'
}