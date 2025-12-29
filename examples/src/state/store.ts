import { signal } from "@preact/signals";
import type { ParseError, SourceMapping } from "../lib/yyjj-wrapper";

export type EditSource = "jsonc" | "yaml" | null;

export const DEFAULT_JSONC = `{
  // サーバー設定
  "server": "localhost",
  "port": 8080,
  /* データベース接続 */
  "database": {
    "host": "db.example.com",
    "name": "myapp"
  }
}`;

// Editor content
export const jsoncContent = signal<string>(DEFAULT_JSONC);
export const yamlContent = signal<string>("");

// Edit source tracking (to prevent infinite loops)
export const editSource = signal<EditSource>(null);

// Error states
export const jsoncError = signal<ParseError | null>(null);
export const yamlError = signal<ParseError | null>(null);

// Filename states
export const jsoncFilename = signal<string | null>(null);
export const yamlFilename = signal<string | null>(null);

// Scroll sync state
export const scrollSyncEnabled = signal<boolean>(true);

// Position mapping states for cursor sync
export const jsoncToYamlMappings = signal<SourceMapping[]>([]);
export const yamlToJsoncMappings = signal<SourceMapping[]>([]);
