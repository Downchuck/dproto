/*******************************************************************************
 * Intermediate structures used for generating class strings
 *
 * These are only used internally, so are not being exported
 *
 * Authors: Matthew Soucy, msoucy@csh.rit.edu
 * Date: Oct 5, 2013
 * Version: 0.0.2
 */
module dproto.intermediate;

import dproto.serialize;

import std.algorithm;
import std.conv;
import std.string;
import std.format;

package:

struct Options {
	string[string] raw;
	alias raw this;
	const void toString(scope void delegate(const(char)[]) sink, FormatSpec!char fmt)
	{
		if(!raw.length) return;
		sink.formattedWrite(" [%-(%s = %s%|, %)]", raw);
	}
}

struct MessageType {
	this(string name) {
		this.name = name;
	}
	string name;
	Options options;
	Field[] fields;
	EnumType[] enumTypes;
	MessageType[] messageTypes;

	const void toString(scope void delegate(const(char)[]) sink, FormatSpec!char fmt)
	{
		if(fmt.spec == 'p') {
			sink.formattedWrite("message %s { ", name);
			foreach(opt, val; options) {
				sink.formattedWrite("option %s = %s; ", opt, val);
			}
		} else {
			sink.formattedWrite("static struct %s {\n", name);
		}
		foreach(et; enumTypes) et.toString(sink, fmt);
		foreach(mt; messageTypes) mt.toString(sink, fmt);
		foreach(field; fields) field.toString(sink, fmt);

		// Methods for serialization and deserialization.
		if(!fmt.flDash && fmt.spec != 'p') {

			// JSON stringify
			import std.json : JSONValue;
			sink("string toJson() {");
			sink(` return "{" ~ `);
			bool firstVal = true;
			foreach(f; fields) {
				if(firstVal == true) {
					firstVal = false;	
				} else {
					sink(` "," ~ `);
				}
				sink(JSONValue(f.name).toString());
				sink.formattedWrite(` ~ ":" ~ %s.toJson() ~ `, f.name, f.name);
			}
			sink(` "}";`);
			sink("}\n");

			// Serialize function
			sink("ubyte[] serialize() ");
			sink("{ auto __a = appender!(ubyte[]); serializeTo(__a); return __a.data; }\n");
			sink("void serializeTo(R)(ref R __r)\n");
			sink("if(isOutputRange!(R, ubyte)) { ");
			foreach(f; fields) {
				sink.formattedWrite("%s.serializeTo(__r);\n", f.name);
			}
			sink("}\n");
			// Deserialize function
			sink("void deserialize(R)(auto ref R __data)\n");
			sink("if(isInputRange!R && is(ElementType!R : const ubyte)) {");
			foreach(f; fields.filter!(a=>a.requirement==Field.Requirement.REQUIRED)) {
				sink.formattedWrite("bool %s_isset = false;\n", f.name);
			}
			sink("while(!__data.empty) { ");
			sink("auto __msgdata = __data.readVarint();\n");
			sink("switch(__msgdata.msgNum()) { ");
			foreach(f; fields) { f.getCase(sink); }
			/// @todo: Safely ignore unrecognized messages
			sink("default: defaultDecode(__msgdata, __data); break;");
			// Close the while and switch
			sink("} } ");

			// Check the required flags (Deprecated in Protobuf 3)
			foreach(f; fields.filter!(a=>a.requirement==Field.Requirement.REQUIRED)) {
				sink.formattedWrite(`enforce(%s_isset, `, f.name);
				sink.formattedWrite(`new DProtoException(`);
				sink.formattedWrite(`"Did not receive expected input \"%s\""));`, f.name);
				sink("\n");
			}
			sink("}\nthis(R)(auto ref R __data)\n");
			sink("if(isInputRange!R && is(ElementType!R : const ubyte))");
			sink("{ deserialize(__data); }\n");
		}
		sink("}\n");
	}

	const void writeFuncs(string prefix, scope void delegate(const(char)[]) sink)
	{
		auto fullname = prefix ~ name ~ ".";
		foreach(e; enumTypes) e.writeFuncs(fullname, sink);
		foreach(m; messageTypes) m.writeFuncs(fullname, sink);
	}

	string toProto() @property const { return "%p".format(this); }
	string toD() @property const { return "%s".format(this); }
}

struct EnumType {
	this(string name) {
		this.name = name.idup;
	}
	string name;
	Options options;
	int[string] values;

	const void toString(scope void delegate(const(char)[]) sink, FormatSpec!char fmt)
	{
		sink.formattedWrite("enum %s {\n", name);
		string suffix = ", ";
		if(fmt.spec == 'p') {
			foreach(opt, val; options) {
				sink.formattedWrite("option %s = %s; ", opt, val);
			}
			suffix = "; ";
		}
		foreach(key, val; values) {
			sink.formattedWrite("%s = %s%s", key, val, suffix);
		}
		sink("}\n");
	}

	const void writeFuncs(string prefix, scope void delegate(const(char)[]) sink)
	{
		auto fullname = prefix ~ name;
		sink(fullname);
		sink(" readProto(string T, R)(ref R src)\n");
		sink.formattedWrite(`if(T == "%s" && `, fullname);
		sink(`(isInputRange!R && is(ElementType!R : const ubyte)))`);
		sink.formattedWrite("{ return src.readVarint().to!(%s)(); }\n", fullname);
	}

	string toProto() @property const { return "%p".format(this); }
	string toD() @property const { return "%s".format(this); }
}

struct Option {
	this(string name, string value) {
		this.name = name.idup;
		this.value = value.idup;
	}
	string name;
	string value;
}

struct Extension {
	ulong minVal = 0;
	ulong maxVal = ulong.max;
}

struct ProtoPackage {
	this(string fileName) {
		this.fileName = fileName.idup;
	}
	string fileName;
	string packageName;
	string[] dependencies;
	EnumType[] enumTypes;
	MessageType[] messageTypes;
	Options options;
	Service[] rpcServices;

	const void toString(scope void delegate(const(char)[]) sink, FormatSpec!char fmt)
	{
		if(fmt.spec == 'p') {
			if(packageName) {
				sink.formattedWrite("package %s; ", packageName);
			}
			foreach(dep; dependencies) {
                               sink.formattedWrite(`import "%s"; `, dep);
			}
		} else {
			foreach(dep;dependencies) {
				sink.formattedWrite(`mixin ProtocolBuffer!"%s";`, dep);
			}
		}
		foreach(e; enumTypes) e.toString(sink, fmt);
		foreach(m; messageTypes) m.toString(sink, fmt);
		foreach(r; rpcServices) r.toString(sink, fmt);
		if(fmt.spec == 'p') {
			foreach(opt, val; options) {
				sink.formattedWrite("option %s = %s; ", opt, val);
			}
		} else {
			foreach(e; enumTypes) e.writeFuncs("", sink);
			foreach(m; messageTypes) m.writeFuncs("", sink);
		}
	}

	string toProto() @property const { return "%p".format(this); }
	string toD() @property const { return "%s".format(this); }
}

struct Field {
	enum Requirement {
		OPTIONAL,
		REPEATED,
		REQUIRED
	}
	this(Requirement labelEnum, string type, string name, uint tag, Options options) {
		this.requirement = labelEnum;
		this.type = type;
		this.name = name;
		this.id = tag;
		this.options = options;
	}
	Requirement requirement;
	string type;
	string name;
	uint id;
	Options options;

	const void toString(scope void delegate(const(char)[]) sink, FormatSpec!char fmt)
	{
		switch(fmt.spec) {
			case 'p':
				if(fmt.width == 3 && requirement != Requirement.REPEATED) {
					sink.formattedWrite("%s %s = %s%p; ",
						type, name, id, options);
				}
				else {
					sink.formattedWrite("%s %s %s = %s%p; ",
						requirement.to!string.toLower(),
						type, name, id, options);
				}
				break;
			default:
				if(!fmt.flDash) {
					getDeclaration(sink);
				} else {
					sink.formattedWrite("%s %s;\n",
						type, name);
				}
				break;
		}
	}

	string toProto() @property const { return "%p".format(this); }
	void getDeclaration(scope void delegate(const(char)[]) sink) const {
		sink(requirement.to!string.capitalize());
		sink.formattedWrite(`Buffer!(%s, "%s", `, id, type);
		if(IsBuiltinType(type)) {
			sink.formattedWrite(`BuffType!"%s"`, type);
		} else {
			sink(type);
		}
		sink(", ");
		sink(options.get("deprecated", "false"));
		if(requirement == Requirement.OPTIONAL) {
			sink(", ");
			if(auto dV = "default" in options) {
				if(!IsBuiltinType(type)) {
					sink.formattedWrite("%s.", type);
				}
				sink(*dV);
			} else {
				if(IsBuiltinType(type)) {
					sink.formattedWrite(`(BuffType!"%s")`, type);
				} else {
					sink.formattedWrite("%s", type);
				}
				sink(".init");
			}
		} else if(requirement == Requirement.REPEATED) {
			sink(", ");
			sink(options.get("packed", "false"));
		}
		sink.formattedWrite(") %s;\n", name);
	}
	void getCase(scope void delegate(const(char)[]) sink) const {
		sink.formattedWrite("case %s:\n", id);
		sink.formattedWrite("%s.deserialize(__msgdata, __data);\n", name);
		if(requirement == Requirement.REQUIRED) {
			sink.formattedWrite("%s_isset = true;\n", name);
		}
		sink("break;\n");
	}
}


struct Service {
	this(string name) {
		this.name = name.idup;
	}
	string name;
	Options options;
	Method[] rpc;

	struct Method {
		this(string name, string documentation, string requestType, string responseType) {
			this.name = name.idup;
			this.documentation = documentation.idup;
			this.requestType = requestType.idup;
			this.responseType = responseType.idup;
		}
		string name;
		string documentation;
		string requestType;
		string responseType;
		Options options;

		const void toString(scope void delegate(const(char)[]) sink, FormatSpec!char fmt)
		{
			switch(fmt.spec) {
				case 'p':
					sink.formattedWrite("rpc %s (%s) returns (%s)", name, requestType, responseType);
					if(options.length > 0) {
						sink(" {\n");
						foreach(opt, val; options) {
							sink.formattedWrite("option %s = %s;\n", opt, val);
						}
						sink("}\n");
					} else {
						sink(";\n");
					}
					break;
				default:
					if(fmt.precision == 3) {
						sink.formattedWrite("%s %s (%s) { %s res; return res; }\n", responseType, name, requestType, responseType);
					} else if(fmt.precision == 2) {
						sink.formattedWrite("void %s (const %s, ref %s);\n", name, requestType, responseType);
					} else if(fmt.precision == 1) {
						sink.formattedWrite("%s %s (%s);\n", responseType, name, requestType);
					}
					break;
			}
		}
	}

	const void toString(scope void delegate(const(char)[]) sink, FormatSpec!char fmt)
	{
		switch(fmt.spec) {
			case 'p':
				sink.formattedWrite("service %s {\n", name);
				break;
			default:
				if(fmt.precision == 3) {
					sink.formattedWrite("class %s {\n", name);
				} else if(fmt.precision == 2 || fmt.precision == 1) {
					sink.formattedWrite("interface %s {\n", name);
				} else {
					return;
				}
				break;
		}
		foreach(m; rpc) m.toString(sink, fmt);
		sink("}\n");
	}

}
