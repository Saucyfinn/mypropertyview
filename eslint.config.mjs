import js from "@eslint/js";
import markdown from "eslint-plugin-markdown";
import jsonc from "eslint-plugin-jsonc";
import jsoncParser from "jsonc-eslint-parser";

export default [
  js.configs.recommended,
  { files: ["**/*.{json,jsonc}"], languageOptions: { parser: jsoncParser }, plugins: { jsonc } },
  { files: ["**/*.md"], plugins: { markdown }, processor: markdown.processors.markdown },
  {
    ignores: [
      "DerivedData/**","build/**","**/*.xcuserdatad/**","**/*.xcworkspace/**","**/*.xcodeproj/**",
      "Pods/**","Carthage/Build/**",".git/**","node_modules/**"
    ]
  }
];
