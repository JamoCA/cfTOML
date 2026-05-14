component {
	this.name = "cfTOML_conformance_" & hash(getCurrentTemplatePath());
	this.sessionManagement = false;
	this.setClientCookies = false;

	// Map /cfTOML to the project root. Adobe CF and Lucee resolve expandPath("../..") relative to the
	// Application.cfc's directory; BoxLang resolves it differently, so compute the path explicitly.
	this.mappings["/cfTOML"] = getDirectoryFromPath(getCurrentTemplatePath()) & "../..";
}
