from session import Session
from PIL import Image


Session(model_path="./skin_512_u2netp.onnx").remove(Image.open("./zuck.jpg"), (512, 512)).save("result.png")
