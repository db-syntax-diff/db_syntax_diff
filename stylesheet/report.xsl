<?xml version="1.0" encoding="euc-jp"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns="http://www.w3.org/TR/xhtml/strict" version="2.0">

<xsl:template match="REPORT">
<HTML><HEAD><TITLE>db_syntax_diff report</TITLE></HEAD>
<BODY>
<H1>db_syntax_diff report</H1>
<HR/>
<TABLE BORDER="1">
<TR><TH>File name</TH><TH>line</TH><TH>level</TH><TH>id</TH><TH>Struct</TH><TH>Message</TH></TR>
<xsl:apply-templates/>
</TABLE>
<HR/>
<P align="right">Copyright NTT, 2009</P>
</BODY>
</HTML>
</xsl:template>


<xsl:template match="FILE">
<xsl:if test="@item_number != '0'">
<xsl:for-each select="REPORT_ITEM">
<xsl:element name="TR">
<xsl:if test="position()=1">
<xsl:element name="TD">
<xsl:attribute name="valign">top</xsl:attribute>
<xsl:attribute name="rowspan"><xsl:value-of select="../@report_item_number"/></xsl:attribute>
<xsl:value-of select="../@name"/><BR/>report items=<xsl:value-of select="../@report_item_number"/>
</xsl:element> <!-- TD element end -->
</xsl:if>
<xsl:element name="TD">
<xsl:value-of select="@line"/>
</xsl:element>
<xsl:element name="TD">
<xsl:value-of select="@level"/>
</xsl:element>
<xsl:element name="TD">
<xsl:value-of select="@id"/>
</xsl:element>
<xsl:element name="TD">
<xsl:value-of select="STRUCT/text()"/>
</xsl:element>
<xsl:element name="TD">
<xsl:value-of select="MESSAGE/text()"/>
</xsl:element>
</xsl:element> <!-- TR element end -->

</xsl:for-each>	<!-- ITEM for-each end-->
</xsl:if> <!-- @item_number not equal 0 -->

<xsl:if test="@item_number = '0'">
<xsl:element name="TR">
<xsl:element name="TD">
<xsl:attribute name="valign">top</xsl:attribute>
<xsl:value-of select="@name"/><BR/>report items=<xsl:value-of select="@item_number"/>
</xsl:element> <!-- TD element end -->
<xsl:element name="TD">
<xsl:attribute name="colspan">4</xsl:attribute>
It is all Embeded SQL statements that can be migrate
</xsl:element> <!-- TD element end -->
</xsl:element> <!-- TR element end -->
</xsl:if> <!-- @item_number equal 0 -->

</xsl:template>

</xsl:stylesheet>
