<?xml version="1.0" encoding="utf-8" ?>
<!-- Copyright (C) 2013 NTT -->
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">

    <xsl:output method="text" encoding="utf-8"/>

    <xsl:strip-space elements="*"/>

    <xsl:template match="REPORT_ITEM">
        <xsl:value-of select="REPLACEPATTERN/@replace_flag"/><xsl:text>,</xsl:text>
        <xsl:value-of select="normalize-space(REPLACEPATTERN/text())"/><xsl:text>,</xsl:text>
        <xsl:text>"</xsl:text><xsl:value-of select="normalize-space(STRUCT/text())"/><xsl:text>",</xsl:text>
        <xsl:value-of select="normalize-space(SOURCE/LINE/text())"/><xsl:text>,</xsl:text>
        <xsl:value-of select="normalize-space(SOURCE/COLUMN/text())"/><xsl:text>,</xsl:text>
        <xsl:value-of select="../@name"/><xsl:text>,</xsl:text>
        <xsl:value-of select="@id"/><xsl:text>,</xsl:text>
        <xsl:value-of select="@type"/><xsl:text>,</xsl:text>
        <xsl:text>"</xsl:text><xsl:value-of select="normalize-space(MESSAGE/text())"/><xsl:text>"</xsl:text>
<xsl:text>
</xsl:text>
    </xsl:template>
<xsl:template match="STRING_ITEM"/>
<xsl:template match="METADATA"/>
</xsl:stylesheet>
