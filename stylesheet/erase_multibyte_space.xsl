<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform" 
  xmlns:str="http://exslt.org/strings"
  extension-element-prefixes="str">
<xsl:output method="xml"/>

<xsl:attribute-set name="report_attr">
  <xsl:attribute name="file_number"><xsl:value-of select="@file_number"/></xsl:attribute>
  <xsl:attribute name="start_time"><xsl:value-of select="@start_time"/></xsl:attribute>
  <xsl:attribute name="finish_time"><xsl:value-of select="@finish_time"/></xsl:attribute>
</xsl:attribute-set>
<xsl:attribute-set name="file_attr">
  <xsl:attribute name="name"><xsl:value-of select="@name"/></xsl:attribute>
  <xsl:attribute name="string_item_number"><xsl:value-of select="@string_item_number"/></xsl:attribute>
  <xsl:attribute name="report_item_number"><xsl:value-of select="@report_item_number"/></xsl:attribute>
  <xsl:attribute name="item_number"><xsl:value-of select="@item_number"/></xsl:attribute>
</xsl:attribute-set>

<xsl:template match="/">
  <xsl:apply-templates select="REPORT"/>
</xsl:template>

<xsl:template match="REPORT">
  <xsl:copy use-attribute-sets="report_attr">
    <xsl:copy-of select="METADATA"/>
    <xsl:apply-templates select="FILE"/>
  </xsl:copy>
</xsl:template>

<xsl:template match="FILE">
  <xsl:copy use-attribute-sets="file_attr">
    <xsl:apply-templates select="STRING_ITEM"/>
    <xsl:copy-of select="REPORT_ITEM"/>
  </xsl:copy>
</xsl:template>

<xsl:template match="STRING_ITEM">
  <xsl:if test="contains(TARGET, '　')">
    <xsl:variable name="source" select="str:tokenize(normalize-space(@line), ':')"/>

    <REPORT_ITEM id="SQL-130-001" type="SQL" level="CHECK_LOW1" score="10">
      <SOURCE>
        <CLASS><xsl:value-of select="$source[1]"/></CLASS>
        <METHOD/>
        <LINE><xsl:value-of select="$source[3]"/></LINE>
        <COLUMN>0</COLUMN>
        <VARIABLE><xsl:value-of select="$source[2]"/></VARIABLE>
      </SOURCE>
      <STRUCT>全角スペース</STRUCT>
      <TARGET><xsl:value-of select="TARGET"/></TARGET>
      <MESSAGE>全角スペースを含むSQLを発行している可能性があります。</MESSAGE>
    </REPORT_ITEM>

  </xsl:if>
</xsl:template>

</xsl:stylesheet>
