package dev.farumazula.datareference;

import java.util.List;
import java.util.Map;

/** A small JSON writer: maps, lists, strings, numbers, booleans and null. */
final class Json {
    private Json() {}

    static String write(Object value) {
        StringBuilder out = new StringBuilder();
        write(out, value, 0);
        return out.toString();
    }

    private static void write(StringBuilder out, Object value, int depth) {
        if (value == null) {
            out.append("null");
        } else if (value instanceof Map<?, ?> map) {
            out.append("{");
            boolean first = true;
            for (Map.Entry<?, ?> entry : map.entrySet()) {
                out.append(first ? "\n" : ",\n").append("  ".repeat(depth + 1));
                first = false;
                string(out, String.valueOf(entry.getKey()));
                out.append(": ");
                write(out, entry.getValue(), depth + 1);
            }
            out.append(first ? "}" : "\n" + "  ".repeat(depth) + "}");
        } else if (value instanceof List<?> list) {
            out.append("[");
            for (int i = 0; i < list.size(); i++) {
                out.append(i == 0 ? "" : ", ");
                write(out, list.get(i), depth + 1);
            }
            out.append("]");
        } else if (value instanceof Number || value instanceof Boolean) {
            out.append(value);
        } else {
            string(out, String.valueOf(value));
        }
    }

    private static void string(StringBuilder out, String text) {
        out.append('"');
        for (char c : text.toCharArray()) {
            switch (c) {
                case '"' -> out.append("\\\"");
                case '\\' -> out.append("\\\\");
                case '\n' -> out.append("\\n");
                case '\r' -> out.append("\\r");
                case '\t' -> out.append("\\t");
                default -> {
                    if (c < 0x20) {
                        out.append(String.format("\\u%04x", (int) c));
                    } else {
                        out.append(c);
                    }
                }
            }
        }
        out.append('"');
    }
}
