import {
  Sheet,
  SheetClose,
  SheetContent,
  SheetTitle,
  SheetTrigger,
} from "@/components/ui/sheet";
import { buttonVariants } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { MenuIcon, StarIcon } from "lucide-react";

export interface NavLink {
  href: string;
  label: string;
}

/**
 * Mobile/tablet navigation drawer (shadcn Sheet, Base UI dialog). Replaces the
 * former hand-rolled <768 and 768-1024 menus with a single drawer for all <lg.
 */
export function MobileNav({
  currentPath,
  links,
}: {
  currentPath: string;
  links: NavLink[];
}) {
  return (
    <Sheet>
      <SheetTrigger
        aria-label="Open navigation menu"
        className="cursor-pointer p-2 text-white transition-colors duration-200 hover:text-yellow-500"
      >
        <MenuIcon className="size-6" />
      </SheetTrigger>
      <SheetContent
        side="right"
        className="w-72 border-white/10 bg-black/95 backdrop-blur-md"
      >
        <SheetTitle className="px-4 pt-4 text-xl font-semibold tracking-tight text-white">
          Blankie
        </SheetTitle>
        <nav className="flex flex-col gap-1 px-2">
          {links.map((l) => (
            <SheetClose
              key={l.href}
              render={
                <a
                  href={l.href}
                  className={cn(
                    "rounded-md px-3 py-2 text-base no-underline transition-colors hover:bg-white/5 hover:text-yellow-500",
                    currentPath === l.href && "text-yellow-500",
                  )}
                >
                  {l.label}
                </a>
              }
            />
          ))}
        </nav>
        <div className="mt-auto flex flex-col gap-2 p-4">
          <a
            href="https://github.com/codybrom/blankie"
            target="_blank"
            rel="noopener noreferrer"
            className={cn(buttonVariants({ variant: "outline" }), "gap-2")}
          >
            <StarIcon className="size-4" />
            Star on GitHub
          </a>
          <a
            href="/?section=download"
            className="bg-primary-blue hover:bg-deep-blue rounded-full px-6 py-2 text-center text-sm font-normal text-white no-underline transition-all duration-300"
          >
            Download
          </a>
        </div>
      </SheetContent>
    </Sheet>
  );
}
