<?xml version="1.0"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
  <xsl:output method="xml" version="1.0" encoding="UTF-8" indent="yes"/>

  <xsl:template match="/submit">
    <job retention_tag="scratch">
      <whiteboard>Provision server for 24 hrs</whiteboard>
      <xsl:apply-templates select="recipe"/>
    </job>
  </xsl:template>

  <xsl:template match="/submit/recipe">
    <recipeSet priority="High">
      <recipe whiteboard="" role="RECIPE_MEMBERS" ks_meta="" kernel_options="" kernel_options_post="">
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
              <xsl:attribute name="value"><xsl:value-of select="distro/@host"/></xsl:attribute>
	    </hostname>
	    <system_type op="=" value="Machine"/>
	  </and>
        </hostRequires>
        <partitions/>
        <task name="/distribution/check-install" role="STANDALONE"/>
        <task name="/kernel/infiniband/ofa-fsdp/env_setup" role="STANDALONE">
          <fetch url="https://github.com/OpenFabrics/fsdp_tests/archive/refs/heads/main.zip#kernel/infiniband/ofa-fsdp/env_setup"/>
          <params>
            <param name="ENV_DRIVER">
              <xsl:attribute name="value"><xsl:value-of select="env/@driver"/></xsl:attribute>
            </param>
            <param name="ENV_NETWORK">
              <xsl:attribute name="value"><xsl:value-of select="env/@network"/></xsl:attribute>
            </param>
          </params>
        </task>
        <task name="/kernel/infiniband/demo" role="STANDALONE">
	  <fetch url="https://github.com/OpenFabrics/fsdp_tests/archive/refs/heads/main.zip#kernel/infiniband/demo"/>
	  <params/>
        </task>
      </recipe>
    </recipeSet>
  </xsl:template>
</xsl:stylesheet>
