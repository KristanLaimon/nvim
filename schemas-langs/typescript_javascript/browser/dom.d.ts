/**
 * Web/DOM Ambient Global Types Definition
 * Injected dynamically by FOX Type Injector
 */

declare var window: Window & typeof globalThis;
declare var document: Document;
declare var console: Console;
declare function fetch(input: any, init?: any): Promise<any>;
