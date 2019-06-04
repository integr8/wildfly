ARG JRE_VERSION

FROM openjdk:${JRE_VERSION}
LABEL Maintainer="Integr8 <contato@integr8.me>" \
  Description="Wildfly Docker Image"

ARG WILDFLY_VERSION
ARG WILDFLY_DOWNLOAD_URL="http://download.jboss.org/wildfly/${WILDFLY_VERSION}/wildfly-${WILDFLY_VERSION}.tar.gz"

ENV JBOSS_HOME /opt/wildfly

WORKDIR /opt

ADD files/* /usr/local/bin/

RUN apk --update add bash && wget ${WILDFLY_DOWNLOAD_URL} -O wildfly.tar.gz \
  && tar -xzf wildfly.tar.gz && rm wildfly.tar.gz && ln -s wildfly-${WILDFLY_VERSION} wildfly \
  && chmod +x /usr/local/bin/*.sh

EXPOSE 8080/tcp 8443/tcp

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
