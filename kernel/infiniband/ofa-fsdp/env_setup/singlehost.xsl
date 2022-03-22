<?xml version="1.0"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
  <xsl:output method="xml" version="1.0" encoding="UTF-8" indent="yes"/>

  <xsl:template match="/submit">
    <job retention_tag="scratch" group="ofa-users">
      <whiteboard>
        <xsl:choose><xsl:when test="whiteboard = ''">RDMA environment setup for singlehost test
        </xsl:when><xsl:otherwise><xsl:value-of select="whiteboard"/>
        </xsl:otherwise></xsl:choose>
      </whiteboard>
      <xsl:apply-templates select="recipe"/>
    </job>
  </xsl:template>

  <xsl:template match="/submit/recipe">
    <recipeSet priority="Urgent">
      <recipe kernel_options="" kernel_options_post="" role="N1" whiteboard="1st machine">
        <xsl:if test="contains(distro/@family, 'Linux8') or contains(distro/@family, 'Fedora')">
          <xsl:attribute name="ks_meta">harness=restraint-rhts</xsl:attribute>
        </xsl:if>
	<autopick random="false"/>
	<watchdog panic="ignore"/>
	<packages/>
	<ks_appends>
          <xsl:choose><xsl:when test="kickstart/@appends != ''">
            <ks_append>
              %post
              <xsl:value-of select="kickstart/@appends"/>
              %end
            </ks_append>
          </xsl:when></xsl:choose>
	</ks_appends>
	<repos/>
	<distroRequires>
	  <and>
	    <distro_family op="=">
	      <xsl:attribute name="value"><xsl:value-of select="distro/@family"/></xsl:attribute>
	    </distro_family>
	    <distro_variant op="=">
	      <xsl:attribute name="value"><xsl:value-of select="distro/@variant"/></xsl:attribute>
	    </distro_variant>
	    <distro_name op="=">
	      <xsl:attribute name="value"><xsl:value-of select="distro/@name"/></xsl:attribute>
	    </distro_name>
	    <distro_arch op="=">
	      <xsl:attribute name="value"><xsl:value-of select="distro/@arch"/></xsl:attribute>
	    </distro_arch>
            <distro_tag op="=">
	      <xsl:attribute name="value"><xsl:value-of select="distro/@tag"/></xsl:attribute>
	    </distro_tag>
	  </and>
	</distroRequires>
        <hostRequires>
          <and>
            <hostname op="=">
              <xsl:attribute name="value"><xsl:value-of select="distro/@machine1"/></xsl:attribute>
            </hostname>
            <system_type op="=" value="Machine"/>
          </and>
        </hostRequires>
	<partitions/>
	<task name="/distribution/check-install" role="STANDALONE">
	  <params/>
	</task>
	<task name="/kernel/infiniband/ofa-fsdp/env_setup" role="STANDALONE">
	  <params>
            <param name="ENV_DRIVER">
              <xsl:attribute name="value"><xsl:value-of select="env/@driver"/></xsl:attribute>
            </param>
            <param name="ENV_NETWORK">
              <xsl:attribute name="value"><xsl:value-of select="env/@network"/></xsl:attribute>
            </param>
          </params>
	</task>
      </recipe>
    </recipeSet>
  </xsl:template>
</xsl:stylesheet>
