component {
	this.name = "cfTOML_tests_" & hash(getCurrentTemplatePath());
	this.sessionManagement = false;
	this.setClientCookies = false;

	// Map /cfTOML to the parent of this file's directory (the project root). Adobe CF and Lucee resolve
	// expandPath("..") relative to the Application.cfc's directory; BoxLang resolves it one level higher,
	// so compute the project root explicitly from the template path to keep the mapping consistent.
	this.mappings["/cfTOML"] = getDirectoryFromPath(getCurrentTemplatePath()) & "..";
}
