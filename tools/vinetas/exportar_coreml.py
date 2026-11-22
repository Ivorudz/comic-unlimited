#!/usr/bin/env python3
"""Pasa el modelo entrenado (modelo.pt) al formato del iPhone (Core ML) y lo deja en la app.

Uso:
    python tools/vinetas/exportar_coreml.py "modelo.pt" [ComicUnlimited/Vinetas.mlmodel]

- Entrada: imagen RGB de 320 × 480 (la app estira la página a ese tamaño).
- Salida "clases": 240 × 160 números (0 fondo, 1 adentro de viñeta, 2 borde). Los recuadros los arma la app.
- Usa el formato "neuralnetwork" (.mlmodel) porque el formato nuevo no se puede crear desde Windows.
Necesita: pip install torch torchvision coremltools
"""
import os, sys
import torch
import coremltools as ct

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import modelo_vinetas as mv  # noqa: E402


class ParaIPhone(torch.nn.Module):
    """Recibe la imagen con valores de 0 a 255 y devuelve directamente la clase de cada punto."""

    def __init__(self, model):
        super().__init__()
        self.model = model
        self.register_buffer('mean', torch.tensor(mv.MEAN).view(1, 3, 1, 1) * 255)
        self.register_buffer('std', torch.tensor(mv.STD).view(1, 3, 1, 1) * 255)

    def forward(self, x):
        return self.model((x - self.mean) / self.std).argmax(1).float()


def main():
    src = sys.argv[1]
    dst = sys.argv[2] if len(sys.argv) > 2 else os.path.join('ComicUnlimited', 'Vinetas.mlmodel')
    model = mv.ModeloVinetas(pretrained=False)
    model.load_state_dict(torch.load(src, map_location='cpu'))
    wrapped = ParaIPhone(model).eval()
    traced = torch.jit.trace(wrapped, torch.rand(1, 3, mv.H, mv.W) * 255)
    ml = ct.convert(traced, convert_to='neuralnetwork',
                    inputs=[ct.ImageType(name='pagina', shape=(1, 3, mv.H, mv.W), color_layout=ct.colorlayout.RGB)],
                    outputs=[ct.TensorType(name='clases')])
    ml = ct.models.neural_network.quantization_utils.quantize_weights(ml, nbits=16)  # mitad de tamaño
    ml.short_description = 'Viñetas de páginas de cómics: 0 fondo, 1 adentro de viñeta, 2 borde.'
    ml.save(dst)
    print(f'Listo: {dst} ({os.path.getsize(dst) / 1e6:.1f} MB)')


if __name__ == '__main__':
    main()
