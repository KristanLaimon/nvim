<?php
// FOX component-alias helper. Authored locally; no upstream implementation used.
namespace App\Console\Commands;

final class BladeNav extends \Illuminate\Console\Command
{
    protected $signature = 'blade-nav:components-aliases';
    protected $description = 'Export registered Blade component source paths for FoxVim';

    public function handle(): int
    {
        $paths = [];
        foreach (app('blade.compiler')->getClassComponentAliases() as $alias => $class) {
            try {
                $source = (new \ReflectionClass($class))->getFileName();
                if ($source !== false) {
                    $paths[$alias] = $source;
                }
            } catch (\ReflectionException $exception) {
                // A runtime alias may reference a class that has been removed.
            }
        }
        $this->line(json_encode($paths, JSON_INVALID_UTF8_SUBSTITUTE | JSON_FORCE_OBJECT));
        return 0;
    }
}
