<?xml version="1.0"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
  <xsl:output method="xml" version="1.0" encoding="UTF-8" indent="yes"/>

  <xsl:template match="/submit">
    <job retention_tag="scratch">
      <whiteboard>
        <xsl:choose><xsl:when test="whiteboard = ''">Linux kernel RDMA subsystem sanity test on OFA FSDP Cluster
        </xsl:when><xsl:otherwise><xsl:value-of select="whiteboard"/>
        </xsl:otherwise></xsl:choose>
      </whiteboard>
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
              <xsl:attribute name="value"><xsl:value-of select="distro/@server"/></xsl:attribute>
            </hostname>
	    <system_type op="=" value="Machine"/>
	  </and>
        </hostRequires>
        <partitions>
          <partition name="/mnt/rdma-ext4" size="30" type="part" fs="ext4"/>
          <partition name="/mnt/rdma-xfs" size="30" type="part" fs="xfs"/>
          <xsl:if test="contains(distro/@family, 'Fedora')">
            <partition name="/home" size="30" type="part" fs="ext4"/>
          </xsl:if>
        </partitions>
        <task name="/distribution/check-install" role="STANDALONE"/>
        <task name="/kernel/infiniband/env_setup" role="SERVERS">
          <fetch url="https://github.com/OpenFabrics/fsdp_tests/archive/refs/heads/main.zip#kernel/infiniband/env_setup"/>
          <params>
            <param name="ENV_DRIVER">
              <xsl:attribute name="value"><xsl:value-of select="env/@driver"/></xsl:attribute>
            </param>
            <param name="ENV_NETWORK">
              <xsl:attribute name="value"><xsl:value-of select="env/@network"/></xsl:attribute>
            </param>
          </params>
        </task>
        <task name="/kernel/infiniband/sanity" role="SERVERS">
	  <fetch url="https://github.com/OpenFabrics/fsdp_tests/archive/refs/heads/main.zip#kernel/infiniband/sanity"/>
	  <params/>
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
              <xsl:attribute name="value"><xsl:value-of select="distro/@client"/></xsl:attribute>
            </hostname>
	    <system_type op="=" value="Machine"/>
	  </and>
        </hostRequires>
        <partitions>
          <partition name="/mnt/rdma-ext4" size="30" type="part" fs="ext4"/>
          <partition name="/mnt/rdma-xfs" size="30" type="part" fs="xfs"/>
          <xsl:if test="contains(distro/@family, 'Fedora')">
            <partition name="/home" size="30" type="part" fs="ext4"/>
          </xsl:if>
        </partitions>
        <task name="/distribution/check-install" role="STANDALONE"/>
        <task name="/kernel/infiniband/env_setup" role="CLIENTS">
          <fetch url="https://github.com/OpenFabrics/fsdp_tests/archive/refs/heads/main.zip#kernel/infiniband/env_setup"/>
          <params>
            <param name="ENV_DRIVER">
              <xsl:attribute name="value"><xsl:value-of select="env/@driver"/></xsl:attribute>
            </param>
            <param name="ENV_NETWORK">
              <xsl:attribute name="value"><xsl:value-of select="env/@network"/></xsl:attribute>
            </param>
          </params>
        </task>
        <task name="/kernel/infiniband/sanity" role="CLIENTS">
	  <fetch url="https://github.com/OpenFabrics/fsdp_tests/archive/refs/heads/main.zip#kernel/infiniband/sanity"/>
	  <params/>
        </task>
      </recipe>
    </recipeSet>
  </xsl:template>
</xsl:stylesheet>
