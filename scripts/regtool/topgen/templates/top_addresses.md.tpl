= Top-Level Memory Map

== IP Blocks

[cols="3,3,3,3,3",options="header"]
|===
| Name | Base Address | Size (bytes) | Bus | Description
% for name, addr, target, iface in mods:
| <<${target}, ${name}>> | 0x${"%08x" % addr} | - | ${iface} | -
% endfor
|===

== Memories

[cols="3,3,3,3,3",options="header"]
|===
| Name | Base Address | Size (bytes) | Bus | Description
% for name, addr, size in mems:
| ${name} | 0x${"%08x" % addr} | 0x${"%08x" % size} | - | -
% endfor
|===
