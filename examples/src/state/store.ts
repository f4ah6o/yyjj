import { signal } from "@preact/signals";
import type { ParseError } from "../lib/yyjj-wrapper";

export type EditSource = "jsonc" | "yaml" | null;

const DEFAULT_JSONC = `{
  // サーバー設定
  "server": "localhost",
  "port": 8080,
  /* データベース接続 */
  "database": {
    "host": "db.example.com",
    "name": "myapp"
  }
}`;

const DEFAULT_YAML = `# サーバー設定
server: localhost
port: 8080
# データベース接続
database:
  host: db.example.com
  name: myapp`;

// Editor content
export const jsoncContent = signal<string>(DEFAULT_JSONC);
export const yamlContent = signal<string>(DEFAULT_YAML);

// Edit source tracking (to prevent infinite loops)
export const editSource = signal<EditSource>(null);

// Error states
export const jsoncError = signal<ParseError | null>(null);
export const yamlError = signal<ParseError | null>(null);
