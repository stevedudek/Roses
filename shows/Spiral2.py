from random import random, randint, choice

from HelperFunctions import*
from math import sin, pi

class Spiral2(object):
	def __init__(self, rosemodel):
		self.name = "Spiral2"        
		self.rose = rosemodel
		self.speed = (randint(0,10)+1) / 0.5
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
						new_d = (d + (2*r)) % maxDistance
						self.rose.set_cell((p,new_d), gradient_wheel(color, intense), r)
					
			self.color1 = changeColor(self.color1, 2)
			self.color2 = changeColor(self.color2, -8)

			self.clock += 1

			yield self.speed