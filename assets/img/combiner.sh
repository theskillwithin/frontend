#!/usr/local/bin/node

/**
 * Utility script that takes individual svg files and combines them into a single file. viewBox is moved from
 * top-level svg element into the symbol definition. Alternate symbols also generated (for IE6-8).
 *
 * "npm install" should install all Node dependencies (not ImageMagick).
 * 
 * dependencies:
 *		+ Node.js
 *
 *		+ ImageMagick
 *
 *		+ Node libraries (running "npm install" should grab all these
 *			+ xmldoc (https://github.com/nfarina/xmldoc)
 *			+ optimist (https://github.com/substack/node-optimist)
 *			+ exec-sync (https://www.npmjs.com/package/exec-sync)
 */
console.log("Carleton SVG Combiner v0.1a");

// pull in external libraries
try {
	var argv = require('optimist')
		.describe('inputDir', 'directory containing svg files')
		.describe('outputDir', 'directory to place output files')
		.describe('basename', 'base filename that will be used to generate both svg and html example files')
		.describe('dims', 'if present, svgs will be scaled to this dimension. Ex: "--dims 100x100"')
		.describe('p', 'if present, svgs will be padded out to the dimensions specified in dims (has no effect if dims omitted)')
		.describe('c', 'if present, \'fill="currentColor"\' will be added to all svg nodes')
		.demand(['inputDir', 'outputDir', 'basename'])
		.argv;
	var fs = require('fs');
	var xmldoc = require('xmldoc');
	var execSync = require('exec-sync');
} catch (e) {
	console.log("Error loading dependencies; did you run 'npm install'?");
	return;
}

try {
	execSync("convert -version");
} catch (e) {
	if (e.toString().indexOf("command not found") > 0) {
		console.log("ImageMagick does not appear to be installed; aborting");
		return;
	}
}

String.prototype.endsWith = function(suffix) { return this.indexOf(suffix, this.length - suffix.length) !== -1; };

var manualXml = "<?xml version=\"1.0\"?>\n<!DOCTYPE svg PUBLIC \"-//W3C//DTD SVG 1.1//EN\" \"http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd\">\n<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\">\n\t<defs>\n";
var manualHtml = "";

// on some browsers this apepars to break things? who knows.
/*
var posterity = "";
for (var i = 2 ; i < process.argv.length ; i++) {
	posterity += (posterity == "" ? "combiner.sh " : " ") + process.argv[i];
}
manualXml += "<!--\nThis SVG document was programmatically generated at " + (new Date()) + " with the following command:\n" + posterity + "\n-->\n";
*/

var dirToCheck = argv.inputDir;
var outputDir = argv.outputDir;

var outputSvgFile = outputDir + "/" + argv.basename + ".svg";
var relativeSvgPath = argv.basename + ".svg";
var outputHtmlFile = outputDir + "/" + argv.basename + ".html";

function writeFile(filename, contents) {
	console.log("Generating output file '" + filename + "'...");
	try {
		fs.writeFileSync(filename, contents);
	} catch (e) {
		console.log("Error writing output file '" + filename + "': " + e);
	}
}

function pad(s, num) {
	var rv = "";
	for (var i = 0 ; i < num ; i++) {
		rv += s;
	}
	return rv;
}

function processNodeForSvg(n, depth) {
	var rv = "";
	var padder = pad("\t", depth+1);
	var goingDeeper = n.children.length > 0;

	if (depth > 1) {
		// console.log("looking at [" + n.name + "]/[" + depth + "]/[" + n.val + "]...[" + n.children.length + "] kids");

		var props = "";
		var fillExists = false;
		for (var prop in n.attr) {
			var propVal = n.attr[prop];
			if (prop == "fill") {
				fillExists = true;
				propVal = "currentColor";
			}

			props += " " + prop + "=\"" + propVal + "\"";
		}

		// if -c passed in on command line, insert a "fill=currentColor" if it was missing
		if (!fillExists && argv.c) {
			props += " fill=\"currentColor\"";
		}

		rv = padder + "<" + n.name + props;
	}

	if (n.val.trim() != "") {
		rv += ">" + n.val + "</" + n.name + ">\n";
	} else {
		if (depth > 1) {
			rv += (goingDeeper ? ">" : "/>") + "\n";
		}

		if (goingDeeper) {
			var children = n.children;
			for (var i = 0 ; i < children.length ; i++) {
				rv += processNodeForSvg(children[i], depth+1);
			}

			if (depth > 1) {
				rv += padder + "</" + n.name + ">\n";
			}
		}
	}

	return rv;
}

try {
	var files = fs.readdirSync(dirToCheck);

	for (var index in files) {
		var f = files[index];

		if (f.endsWith(".svg")) {
			console.log("processing " + f + "...");
			var symbolName = f.substring(0, f.indexOf(".svg"));

			try {
				console.log("\tgenerating png's...");
				
				// see http://www.imagemagick.org/Usage/crop/#extent
				var scaleCmd = argv.dims == undefined ? "" : "-resize " + argv.dims + " ";
				if (scaleCmd != "" && argv.p) { scaleCmd += "-extent " + argv.dims + " -gravity center "; }

				var cmd = "convert " + scaleCmd + "-background transparent -threshold 99% " + dirToCheck + "/" + f + " " + outputDir + "/" + relativeSvgPath + "." + symbolName + ".png";
				execSync(cmd);
				

				// doing it this way fails for items that don't ahve a color set (the ones that can't be tinted without -c)
				// cmd = "convert -background transparent -threshold 0% " + dirToCheck + "/" + f + " " + outputDir + "/" + symbolName + "Alt.png";
				cmd = "convert " + outputDir + "/" + relativeSvgPath + "." + symbolName + ".png -fuzz 95% -fill white -opaque black " + outputDir + "/" + relativeSvgPath + "." + symbolName + "Alt.png";
				execSync(cmd);
			} catch (e) {
				console.log("error generating png with command [" + cmd + "]: [" + e + "]");
			}

			try {
				console.log("\tparsing xml...");
				fileData = fs.readFileSync(dirToCheck + "/" + f);

				if (fileData) {
					var document = new xmldoc.XmlDocument(fileData.toString('utf8'));

					var symbolXml = "\t\t<symbol id=\"" + symbolName + "\" role=\"img\" viewBox=\"" + document.attr.viewBox + "\">\n";
					symbolXml += "\t\t\t<title>" + symbolName + " icon</title>\n";

					symbolXml += processNodeForSvg(document, 1);

					var usage = "<svg title=\"" + symbolName + " icon\"><use xlink:href=\"" + relativeSvgPath + "#" + symbolName + "\"/></svg>";
					var usageAlt = "<svg title=\"" + symbolName + " icon\"><use xlink:href=\"" + relativeSvgPath + "#" + symbolName + "Alt\"/></svg>";
					manualHtml += "<tr>" +
										"<td>" + symbolName + "</td>" +
										"<td>" + usage + "</td>" +
										"<td class='tinted'>" + usage + "</td>" +
										"<td>" + usageAlt + "</td>" +
										"<td class='tinted'>" + usageAlt + "</td>" +
										"<td>" + "<img src='" + relativeSvgPath + "." + symbolName + ".png'></td>" +
										"<td>" + "<img src='" + relativeSvgPath + "." + symbolName + "Alt.png'></td>" +
									"</tr>";

					symbolXml += "\t\t</symbol>\n";
					// manualXml += "\t\t<symbol id=\"" + symbolName + "Alt\"><svg><use xlink:href=\"" + relativeSvgPath + "#" + symbolName + "\"/></svg></symbol>\n";

					manualXml += symbolXml;
					manualXml += symbolXml.replace(/id="(.*)" role/, 'id="\$1Alt" role');
				}
			} catch (e) {
				throw err;
			}

			// console.log(manualXml);
			// return;
		}
	}
} catch (e) {
	console.log("Unable to read directory '" + dirToCheck + "'");
}

manualXml += "\t</defs>\n</svg>";

// console.log("--- OUTPUT ---");
// console.log(manualXml);

manualHtml = "<html>\n<head>\n<style>.tinted { color: purple }\ntd { background-color: lightgrey; }</style><meta http-equiv=\"X-UA-Compatible\" content=\"UE=Edge\">\n<script src=\"svg4everybody.ie8.min.js\"></script>\n</head>\n<body>\n<H2>Confirmation / Sample Page</H2><table border=1 width=100%><tr><th>symbol name</th><th>basic svg</th><th>basic svg styled with color=purple<br>(try running again with -c if not getting colors you expect)</th><th>alternate svg</th><th>alternate svg styled with color=purple</th><th>basic png for ie8 fallback</th><th>alt png for ie8 fallback</th></tr>" + manualHtml + "\n</table></body>\n</html>";

writeFile(outputSvgFile, manualXml);
writeFile(outputHtmlFile, manualHtml);