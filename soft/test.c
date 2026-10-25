#include <SDL2/SDL.h>
#include <stdint.h>
#include <stdbool.h>
#include "lib2d.h"

// #define SCREEN_WIDTH 640
// #define SCREEN_HEIGHT 480


int main(int argc, char* argv[]) {
    if (SDL_Init(SDL_INIT_VIDEO) < 0) return 1;

    SDL_Window* window = SDL_CreateWindow(
        "Custom CPU Display",
        SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
        SCREEN_WIDTH, SCREEN_HEIGHT, 0
    );

    SDL_Renderer* renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED);
    
    // Texture qui sert de VRAM virtuelle (format ARGB8888 ou RGBA8888)
    SDL_Texture* texture = SDL_CreateTexture(
        renderer,
        SDL_PIXELFORMAT_ARGB8888,
        SDL_TEXTUREACCESS_STREAMING,
        SCREEN_WIDTH, SCREEN_HEIGHT
    );

    // Framebuffer virtuel : 1 uint32_t par pixel (0xAARRGGBB)

    bool running = true;
    SDL_Event event;

    while (running) {
        // 1. Gestion de la fermeture de fenêtre
        while (SDL_PollEvent(&event)) {
            if (event.type == SDL_QUIT) running = false;
        }
        /*for(int i = 0; i<SCREEN_WIDTH; i+=SCREEN_WIDTH/40){
            draw_line(SCREEN_WIDTH/2, SCREEN_HEIGHT/2, i, 0, 1);
        }
        for(int i = 0; i<SCREEN_HEIGHT; i+=SCREEN_HEIGHT/40){
            draw_line(SCREEN_WIDTH/2, SCREEN_HEIGHT/2, SCREEN_WIDTH, i, 1);
        }
        for(int i = SCREEN_WIDTH; i>0; i-=SCREEN_WIDTH/40){
            draw_line(SCREEN_WIDTH/2, SCREEN_HEIGHT/2, i, SCREEN_HEIGHT, 1);
        }
        for(int i = SCREEN_HEIGHT; i>0; i-=SCREEN_HEIGHT/40){
            draw_line(SCREEN_WIDTH/2, SCREEN_HEIGHT/2, 0, i, 1);
        }*/
        drawFilledTriangle(100, 100, 150, 300, 40, 400, 1);
        drawFilledTriangle(600, 450, 150, 300, 40, 400, 1);
        // 3. Mise à jour de l'affichage (Transfert VRAM -> Écran)
        SDL_UpdateTexture(texture, NULL, framebuffer, SCREEN_WIDTH * sizeof(uint32_t));
        SDL_RenderClear(renderer);
        SDL_RenderCopy(renderer, texture, NULL, NULL);
        SDL_RenderPresent(renderer);

        SDL_Delay(16); // ~60 FPS
    }

    SDL_DestroyTexture(texture);
    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(window);
    SDL_Quit();

    return 0;
}
