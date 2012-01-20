<?xml version="1.0" encoding="utf-8" ?>
<!-- Copyright (C) 2010 NTT -->
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
  <xsl:output method="xml"/>

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
    <xsl:choose>
      <xsl:when test="preceding-sibling::REPORT_ITEM[@id=current()/@id and SOURCE/LINE/text()=current()/SOURCE/LINE/text() and SOURCE/COLUMN/text()=current()/SOURCE/COLUMN/text()]"/>
      <xsl:otherwise>
        <xsl:copy>
          <xsl:apply-templates select="@*|node()"/>
        </xsl:copy>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>

</xsl:stylesheet>
