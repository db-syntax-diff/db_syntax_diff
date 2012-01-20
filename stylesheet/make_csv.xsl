<?xml version="1.0" encoding="utf-8" ?>
<!-- Copyright (C) 2010 NTT -->
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">

<xsl:output method="text" encoding="Shift_JIS"/>

<xsl:strip-space elements="*"/>

<xsl:template match="REPORT_ITEM">
<xsl:value-of select="../@name"/>,<xsl:value-of select="normalize-space(SOURCE/CLASS/text())"/>,<xsl:value-of select="normalize-space(SOURCE/METHOD/text())"/>,<xsl:value-of select="normalize-space(SOURCE/LINE/text())"/>,<xsl:value-of select="normalize-space(SOURCE/COLUMN/text())"/>,<xsl:value-of select="@id"/>,<xsl:value-of select="@type"/>,<xsl:value-of select="@level"/>,"<xsl:value-of select="normalize-space(MESSAGE/text())"/>","<xsl:value-of select="normalize-space(TARGET/text())"/>"
</xsl:template>
<xsl:template match="STRING_ITEM"/>
<xsl:template match="METADATA"/>
</xsl:stylesheet>
