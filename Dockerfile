FROM openjdk:8-jre-alpine
LABEL Maintainer="Integr8 <fabioluciano@php.net>" \
  Description="Wildfly Docker Image"

ARG WILDFLY_VERSION
ARG WILDFLY_DOWNLOAD_URL="http://download.jboss.org/wildfly/${WILDFLY_VERSION}/wildfly-${WILDFLY_VERSION}.tar.gz"

ENV JBOSS_HOME /opt/wildfly

WORKDIR /opt

RUN apk --update add bash && \
  wget ${WILDFLY_DOWNLOAD_URL} -O wildfly.tar.gz && directory=$(tar tfz wildfly.tar.gz --exclude '*/*') \
  && tar -xzf wildfly.tar.gz && rm wildfly.tar.gz && ln -s wildfly-${WILDFLY_VERSION} wildfly

ADD files/* /usr/local/bin/

RUN chmod +x /usr/local/bin/*.sh

EXPOSE 8080/tcp 8443/tcp

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]