{# VEP-Schema DDS IDL Template #}
{# Generates OMG IDL 4.2 compatible output for CycloneDDS/FastDDS #}
{# #}
{# Type mappings: #}
{#   int8/uint8 → octet (DDS has no signed octet) #}
{#   int16 → short, uint16 → unsigned short #}
{#   int32 → long, uint32 → unsigned long #}
{#   int64 → long long, uint64 → unsigned long long #}
{#   boolean → boolean #}
{#   float → float, double → double #}
{#   string → string #}
{#   T[] → sequence<T> #}
{# #}
{# (C) 2025 VEP Contributors - Apache 2.0 #}
// Generated from {{ item.name }}.ifex by vep-schema
// DO NOT EDIT - regenerate with: ./tools/run.sh generate-idl

{% set filename_upper = item.name|upper|replace("-", "_")|replace(".", "_") %}
#ifndef {{ filename_upper }}_IDL
#define {{ filename_upper }}_IDL

{# Type mappings: IFEX → DDS IDL #}
{% set typedefs = dict() %}
{% set x=typedefs.__setitem__("int8", "octet") %}
{% set x=typedefs.__setitem__("int16", "short") %}
{% set x=typedefs.__setitem__("int32", "long") %}
{% set x=typedefs.__setitem__("int64", "long long") %}
{% set x=typedefs.__setitem__("uint8", "octet") %}
{% set x=typedefs.__setitem__("uint16", "unsigned short") %}
{% set x=typedefs.__setitem__("uint32", "unsigned long") %}
{% set x=typedefs.__setitem__("uint64", "unsigned long long") %}
{% set x=typedefs.__setitem__("boolean", "boolean") %}
{% set x=typedefs.__setitem__("float", "float") %}
{% set x=typedefs.__setitem__("double", "double") %}
{% set x=typedefs.__setitem__("string", "string") %}

{# Macro to convert IFEX types to DDS IDL #}
{% macro convert_type(datatype) -%}
  {%- set is_array = datatype.endswith('[]') -%}
  {%- if is_array -%}
    {%- set base = datatype[:-2] -%}
  {%- else -%}
    {%- set base = datatype -%}
  {%- endif -%}
  {%- if base in typedefs -%}
    {%- set mapped = typedefs[base] -%}
  {%- else -%}
    {%- set mapped = base -%}
  {%- endif -%}
  {%- if is_array -%}
sequence<{{ mapped }}>
  {%- else -%}
{{ mapped }}
  {%- endif -%}
{%- endmacro %}

{# Macro to check if enum has non-sequential values #}
{# Returns 'true' if any option.value != its index, empty otherwise #}
{% macro enum_is_sparse(options) -%}
  {%- for opt in options -%}
    {%- if opt.value != loop.index0 -%}true{%- endif -%}
  {%- endfor -%}
{%- endmacro %}

{# Macro to get base type from datatype (strips [] suffix) #}
{% macro base_type(datatype) -%}
  {%- if datatype.endswith('[]') -%}
{{ datatype[:-2] }}
  {%- else -%}
{{ datatype }}
  {%- endif -%}
{%- endmacro %}

{% for n in item.namespaces %}
{# Build set of all struct names in this namespace #}
{% set struct_names = [] %}
{% for s in n.structs %}
{% set _ = struct_names.append(s.name) %}
{% endfor %}

{# Find structs that need forward declarations #}
{# A struct needs forward decl if it's referenced before it's defined #}
{% set forward_decls = [] %}
{% set seen_structs = [] %}
{% for s in n.structs %}
{% for m in s.members %}
{% set member_base = base_type(m.datatype)|trim %}
{# If member references a struct we haven't seen yet, it needs forward decl #}
{% if member_base in struct_names and member_base not in seen_structs and member_base != s.name %}
{% if member_base not in forward_decls %}
{% set _ = forward_decls.append(member_base) %}
{% endif %}
{% endif %}
{% endfor %}
{% set _ = seen_structs.append(s.name) %}
{% endfor %}
module {{ n.name }} {
{% if n.description %}
    // {{ n.description }}
{% endif %}

{# Generate forward declarations for recursive/out-of-order struct references #}
{% if forward_decls %}
    // Forward declarations
{% for fwd in forward_decls %}
    struct {{ fwd }};
{% endfor %}

{% endif %}
{# Process typedefs first #}
{% for t in n.typedefs %}
{% if t.datatype in typedefs %}
  {% set type = typedefs[t.datatype] %}
{% else %}
  {% set type = t.datatype %}
{% endif %}
{% set x=typedefs.__setitem__(t.name, type) %}
    typedef {{ convert_type(t.datatype) }} {{ t.name }};
{% endfor %}

{# Generate enums #}
{% for e in n.enumerations %}
    // {{ e.description|default("Enumeration " + e.name, true) }}
{# Check if enum is sparse (has gaps in values) #}
{% set ns = namespace(sparse=false) %}
{% for opt in e.options %}
{% if opt.value != loop.index0 %}
{% set ns.sparse = true %}
{% endif %}
{% endfor %}
{% if ns.sparse %}
    @bit_bound(8)
    enum {{ e.name }} {
{% for opt in e.options %}
        @value({{ opt.value }}) {{ opt.name }}{% if not loop.last %},{% endif %}

{% endfor %}
    };
{% else %}
    enum {{ e.name }} {
{% for opt in e.options %}
        {{ opt.name }}{% if not loop.last %},{% endif %}    // = {{ opt.value }}
{% endfor %}
    };
{% endif %}

{% endfor %}
{# Generate structs #}
{% for s in n.structs %}
    // {{ s.description|default("Struct " + s.name, true) }}
    struct {{ s.name }} {
{% for m in s.members %}
        {{ convert_type(m.datatype) }} {{ m.name }};
{% endfor %}
    };
{% if s.members|selectattr("name", "equalto", "path")|list %}
    #pragma keylist {{ s.name }} path
{% endif %}

{% endfor %}
};  // module {{ n.name }}

{% endfor %}
#endif // {{ filename_upper }}_IDL
