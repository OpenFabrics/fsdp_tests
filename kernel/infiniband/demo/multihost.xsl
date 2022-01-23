<?xml version="1.0"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
  <xsl:output method="xml" version="1.0" encoding="UTF-8" indent="yes"/>

  <xsl:template match="/submit">
    <job retention_tag="scratch">
      <whiteboard>Provision server for 1-hr</whiteboard>
      <xsl:apply-templates select="recipe"/>
    </job>
  </xsl:template>

  <xsl:template match="/submit/recipe">
    <recipeSet priority="High">
      <recipe role="SERVERS" whiteboard="1st machine" ks_meta="" kernel_options="" kernel_options_post="">
        <autopick random="false"/>
        <watchdog panic="ignore"/>
        <packages/>
        <ks_appends/>
        <repos/>
        <distroRequires>
          <and>
	    <distro_family op="=">
              <xsl:attribute name="value"><xsl:value-of select="distro/@family"/></xsl:attribute>
	    </distro_family>
	    <distro_variant op="=">
              <xsl:attribute name="value"><xsl:value-of select="distro/@variant"/></xsl:attribute>
	    </distro_variant>
	    <distro_distro op="=">
              <xsl:attribute name="value"><xsl:value-of select="distro/@distro"/></xsl:attribute>
	    </distro_distro>
	    <distro_arch op="=">
              <xsl:attribute name="value"><xsl:value-of select="distro/@arch"/></xsl:attribute>
	    </distro_arch>
	</and> 
        </distroRequires>
	<hostRequires>
          <and>
	    <hostname op="=">
              <xsl:attribute name="value"><xsl:value-of select="distro/@host1"/></xsl:attribute>
            </hostname>
	    <system_type op="=" value="Machine"/>
	  </and>
        </hostRequires>
        <partitions/>
        <task name="/distribution/check-install" role="STANDALONE"/>
        <task name="/kernel/infiniband/demo" role="SERVERS">
          <fetch url="https://github.com/OpenFabrics/fsdp_tests#infiniband/demo"/>
	  <params/>
        </task>
        <task name="/distribution/reservesys" role="STANDALONE">
          <params>
            <param name="RESERVETIME" value="3600"/>
          </params>
        </task>
      </recipe>
      <recipe role="CLIENTS" whiteboard="2nd machine" ks_meta="" kernel_options="" kernel_options_post="">
        <autopick random="false"/>
        <watchdog panic="ignore"/>
        <packages/>
        <ks_appends/>
        <repos/>
        <distroRequires>
          <and>
	    <distro_family op="=">
              <xsl:attribute name="value"><xsl:value-of select="distro/@family"/></xsl:attribute>
	    </distro_family>
	    <distro_variant op="=">
              <xsl:attribute name="value"><xsl:value-of select="distro/@variant"/></xsl:attribute>
	    </distro_variant>
	    <distro_distro op="=">
              <xsl:attribute name="value"><xsl:value-of select="distro/@distro"/></xsl:attribute>
	    </distro_distro>
	    <distro_arch op="=">
              <xsl:attribute name="value"><xsl:value-of select="distro/@arch"/></xsl:attribute>
	    </distro_arch>
	</and> 
        </distroRequires>
	<hostRequires>
          <and>
	    <hostname op="=">
              <xsl:attribute name="value"><xsl:value-of select="distro/@host2"/></xsl:attribute>
            </hostname>
	    <system_type op="=" value="Machine"/>
	  </and>
        </hostRequires>
        <partitions/>
        <task name="/distribution/check-install" role="STANDALONE"/>
        <task name="/kernel/infiniband/demo" role="CLIENTS">
          <fetch url="https://github.com/OpenFabrics/fsdp_tests#infiniband/demo"/>
	  <params/>
        </task>
        <task name="/distribution/reservesys" role="STANDALONE">
          <params>
            <param name="RESERVETIME" value="3600"/>
          </params>
        </task>
      </recipe>
    </recipeSet>
  </xsl:template>
</xsl:stylesheet>      