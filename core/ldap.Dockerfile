FROM osixia/openldap:1.5.0

# Replace the default memberof overlay configuration with one that supports groupOfNames
RUN rm -f /container/service/slapd/assets/config/bootstrap/ldif/03-memberOf.ldif
COPY ldap-bootstrap/03-memberOf.ldif /container/service/slapd/assets/config/bootstrap/ldif/
