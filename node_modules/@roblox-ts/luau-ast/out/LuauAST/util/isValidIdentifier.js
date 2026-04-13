"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.isValidIdentifier = exports.LUAU_IDENTIFIER_REGEX = exports.LUAU_RESERVED_KEYWORDS = void 0;
exports.LUAU_RESERVED_KEYWORDS = new Set([
    "and",
    "break",
    "do",
    "else",
    "elseif",
    "end",
    "false",
    "for",
    "function",
    "if",
    "in",
    "local",
    "nil",
    "not",
    "or",
    "repeat",
    "return",
    "then",
    "true",
    "until",
    "while",
]);
exports.LUAU_IDENTIFIER_REGEX = /^[A-Za-z_][A-Za-z0-9_]*$/;
function isValidIdentifier(id) {
    return !exports.LUAU_RESERVED_KEYWORDS.has(id) && exports.LUAU_IDENTIFIER_REGEX.test(id);
}
exports.isValidIdentifier = isValidIdentifier;
//# sourceMappingURL=isValidIdentifier.js.map