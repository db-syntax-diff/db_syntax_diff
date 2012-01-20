<?xml version="1.0" encoding="utf-8" ?>
<!-- Copyright (C) 2010 NTT -->
<xsl:stylesheet version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform" 
  xmlns:str="http://exslt.org/strings"
  extension-element-prefixes="str">
  <xsl:output method="xml"/>
  <xsl:param name="product_val">PostgreSQL</xsl:param>
  <xsl:param name="version_val">8.3</xsl:param>

  <xsl:template match="node()">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="@*">
    <xsl:attribute namespace="{namespace-uri()}" name="{name()}">
      <xsl:value-of select="."/>
    </xsl:attribute>
  </xsl:template>

  <xsl:template match="REPORT_ITEM">

    <xsl:if test="count(TARGETDBMS)=0 or TARGETDBMS/DBMS[normalize-space(./PRODUCT/text())!=$product_val]">
      <xsl:copy-of select="."/>
    </xsl:if>

    <xsl:if test="TARGETDBMS/DBMS[normalize-space(./PRODUCT/text())=$product_val]">
      <xsl:variable name="res_ver" select="str:tokenize(normalize-space(TARGETDBMS/DBMS/VERSION/text()), '.')"/>
      <xsl:variable name="spc_ver" select="str:tokenize(normalize-space($version_val), '.')"/>

      <xsl:variable name="hasNaN">
        <xsl:call-template name="checkNaN">
          <xsl:with-param name="tmp_spc_ver" select="$spc_ver"/>
        </xsl:call-template>
      </xsl:variable>

      <xsl:choose>
        <xsl:when test="contains($hasNaN, 'true')">
          <xsl:copy-of select="."/>
        </xsl:when>
        <xsl:when test="$res_ver[1] &gt; $spc_ver[1]">
          <xsl:copy-of select="."/>
        </xsl:when>
        <xsl:when test="$res_ver[1] = $spc_ver[1] and $res_ver[2] &gt; $spc_ver[2]">
          <xsl:copy-of select="."/>
        </xsl:when>
        <xsl:when test="$res_ver[1] = $spc_ver[1] and $res_ver[2] = $spc_ver[2] and $res_ver[3] &gt; $spc_ver[3]">
          <xsl:copy-of select="."/>
      </xsl:when>
      </xsl:choose>
    </xsl:if>

  </xsl:template>

  <xsl:template name="checkNaN">
    <xsl:param name="tmp_spc_ver"/>
    <xsl:for-each select="$tmp_spc_ver">
      <xsl:if test="'NaN' = string(number(number(.)))">
        <xsl:value-of select="'true'"/>
      </xsl:if>
    </xsl:for-each>
  </xsl:template>

</xsl:stylesheet>
