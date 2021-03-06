from random import random, randint, choice

from HelperFunctions import*
from math import sin, pi

class Spiral(object):
	def __init__(self, rosemodel):
		self.name = "Spiral"        
		self.rose = rosemodel
		self.speed = 1
		self.color1 = randColor()
		self.color2 = randColor()
		self.clock = 0
		          
	def next_frame(self):
		
		while (True):
			for r in range(maxRose):
				for p in range(maxPetal):
					for d in range(maxDistance):
						color = self.color1 if (p + self.clock) % 2 else self.color2
						intense = (sin( pi * ((d + self.clock) % maxDistance) / (maxDistance+1)  ) + 1) / 2
						if intense < 0.25:
							intense = 0.25
						self.rose.set_cell(((p+r)%maxPetal, (d+r)%maxDistance), gradient_wheel(color, intense), r)
					
			self.color1 = changeColor(self.color1, 1)
			self.color2 = changeColor(self.color2, -4)

			self.clock += 1

			yield self.speed