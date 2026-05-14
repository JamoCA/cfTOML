<cfscript>
// iso8601 mode: pass through verbatim
assertEquals("1979-05-27T07:32:00-08:00", parser.parseRFC3339("1979-05-27T07:32:00-08:00", "iso8601"), "Datetime iso: offset datetime passthrough");
assertEquals("1979-05-27T07:32:00", parser.parseRFC3339("1979-05-27T07:32:00", "iso8601"), "Datetime iso: local datetime passthrough");
assertEquals("1979-05-27", parser.parseRFC3339("1979-05-27", "iso8601"), "Datetime iso: local date passthrough");
assertEquals("07:32:00", parser.parseRFC3339("07:32:00", "iso8601"), "Datetime iso: local time passthrough");

// javatime mode: returns Java time objects (assert via getClass().getName())
assertEquals("java.time.OffsetDateTime", parser.parseRFC3339("1979-05-27T07:32:00-08:00", "javatime").getClass().getName(), "Datetime javatime: offset datetime is OffsetDateTime");
assertEquals("java.time.LocalDateTime", parser.parseRFC3339("1979-05-27T07:32:00", "javatime").getClass().getName(), "Datetime javatime: local datetime is LocalDateTime");
assertEquals("java.time.LocalDate", parser.parseRFC3339("1979-05-27", "javatime").getClass().getName(), "Datetime javatime: local date is LocalDate");
assertEquals("java.time.LocalTime", parser.parseRFC3339("07:32:00", "javatime").getClass().getName(), "Datetime javatime: local time is LocalTime");

// cfdate mode: returns CFML date objects. Verification uses component accessors rather than mask-based
// formatting because dateTimeFormat()'s month-vs-minute interpretation of "mm" differs between Adobe CF,
// Lucee (CFML convention: mm=month, nn=minute) and BoxLang (Java SimpleDateFormat: mm=minute).
parsed = parser.parseRFC3339("1979-05-27", "cfdate");
assertEquals(1979, year(parsed), "Datetime cfdate: local date year");
assertEquals(5,    month(parsed), "Datetime cfdate: local date month");
assertEquals(27,   day(parsed), "Datetime cfdate: local date day");

parsed = parser.parseRFC3339("07:32:00", "cfdate");
assertEquals(7,    hour(parsed), "Datetime cfdate: local time hour");
assertEquals(32,   minute(parsed), "Datetime cfdate: local time minute");
assertEquals(0,    second(parsed), "Datetime cfdate: local time second");

// Invalid input throws
assertThrows("cfTOML\.ParseError", function() {
	parser.parseRFC3339("not-a-date", "iso8601");
}, "Datetime: invalid input throws ParseError");

// cfdate mode: LocalDateTime parses each component verbatim from the source
parsed = parser.parseRFC3339("1979-05-27T07:32:00", "cfdate");
assertEquals(1979, year(parsed), "Datetime cfdate: local datetime year");
assertEquals(5,    month(parsed), "Datetime cfdate: local datetime month");
assertEquals(27,   day(parsed), "Datetime cfdate: local datetime day");
assertEquals(7,    hour(parsed), "Datetime cfdate: local datetime hour");
assertEquals(32,   minute(parsed), "Datetime cfdate: local datetime minute");
assertEquals(0,    second(parsed), "Datetime cfdate: local datetime second");

// cfdate mode: OffsetDateTime converts to server-local time so the returned datetime represents the
// same instant as the source. Wall-clock varies by server zone, so verify zone-independently by
// comparing two equivalent sources (07:32 in -08:00 is 15:32 UTC).
zParsed = parser.parseRFC3339("1979-05-27T15:32:00Z",      "cfdate");
offParsed = parser.parseRFC3339("1979-05-27T07:32:00-08:00", "cfdate");
assertEquals(hour(zParsed),   hour(offParsed),   "Datetime cfdate: equal UTC instants - same local hour");
assertEquals(minute(zParsed), minute(offParsed), "Datetime cfdate: equal UTC instants - same local minute");
assertEquals(day(zParsed),    day(offParsed),    "Datetime cfdate: equal UTC instants - same local day");

// cfdate mode: space separator instead of T
parsed = parser.parseRFC3339("1979-05-27 07:32:00", "cfdate");
assertEquals(1979, year(parsed), "Datetime cfdate: space-separator datetime year");
assertEquals(5,    month(parsed), "Datetime cfdate: space-separator datetime month");
assertEquals(32,   minute(parsed), "Datetime cfdate: space-separator datetime minute");

// cfdate mode: lowercase t separator
parsed = parser.parseRFC3339("1979-05-27t07:32:00", "cfdate");
assertEquals(1979, year(parsed), "Datetime cfdate: lowercase-t datetime year");
assertEquals(5,    month(parsed), "Datetime cfdate: lowercase-t datetime month");
assertEquals(32,   minute(parsed), "Datetime cfdate: lowercase-t datetime minute");

// cfdate mode: fractional-second milliseconds survive to the CFML date (truncate beyond 3 digits, right-pad shorter)
assertEquals(456, datePart("l", parser.parseRFC3339("1979-05-27T07:32:00.456", "cfdate")), "Datetime cfdate: 3-digit milliseconds preserved on local datetime");
assertEquals(700, datePart("l", parser.parseRFC3339("1979-05-27T07:32:00.7", "cfdate")), "Datetime cfdate: 1-digit fractional second right-pads to 700ms");
assertEquals(123, datePart("l", parser.parseRFC3339("1979-05-27T07:32:00.123456789", "cfdate")), "Datetime cfdate: sub-millisecond precision truncated to 3 digits");
assertEquals(456, datePart("l", parser.parseRFC3339("07:32:00.456", "cfdate")), "Datetime cfdate: milliseconds preserved on local time");
assertEquals(456, datePart("l", parser.parseRFC3339("1979-05-27T07:32:00.456Z", "cfdate")), "Datetime cfdate: milliseconds preserved across offset-to-local conversion");
</cfscript>
