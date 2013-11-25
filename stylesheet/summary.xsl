<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns="http://www.w3.org/TR/xhtml/strict" version="2.0">

<xsl:template match="REPORT">
<HTML><HEAD><TITLE>db_syntax_diff report summary</TITLE></HEAD>
<BODY>
<H1>db_syntax_diff report summary</H1>
<HR/>
<TABLE BORDER="1">
<TR><TH>File name</TH><TH>report items</TH></TR>
<xsl:apply-templates/>
</TABLE>
<HR/>
<P align="right">Copyright NTT, 2009</P>
</BODY>
</HTML>
</xsl:template>


<xsl:template match="FILE">
<xsl:for-each select=".">
<xsl:element name="TR">
<xsl:element name="TD">
<xsl:value-of select="@name"/>
</xsl:element>
<xsl:element name="TD">
<xsl:value-of select="@report_item_number"/>
</xsl:element>
</xsl:element> <!-- TR element end -->

</xsl:for-each>	<!-- FILE for-each end-->
</xsl:template>

</xsl:stylesheet>
